#include "mpvobject.h"

#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QQuickWindow>
#include <QMetaObject>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>

#include <mpv/client.h>
#include <mpv/render_gl.h>

namespace {

// mpv's render API asks the host for the address of a named OpenGL
// function; Qt's OpenGL context already resolved these, so just hand
// them back through QOpenGLContext::getProcAddress.
void *getProcAddressMpv(void *ctx, const char *name)
{
    Q_UNUSED(ctx)
    QOpenGLContext *glctx = QOpenGLContext::currentContext();
    if (!glctx)
        return nullptr;
    return reinterpret_cast<void *>(glctx->getProcAddress(QByteArray(name)));
}

QVariant mpvNodeToVariant(mpv_node *node);

QVariantList mpvNodeListToVariant(mpv_node_list *list)
{
    QVariantList result;
    if (!list)
        return result;
    for (int i = 0; i < list->num; ++i)
        result.append(mpvNodeToVariant(&list->values[i]));
    return result;
}

QVariantMap mpvNodeMapToVariant(mpv_node_list *list)
{
    QVariantMap result;
    if (!list)
        return result;
    for (int i = 0; i < list->num; ++i)
        result.insert(QString::fromUtf8(list->keys[i]), mpvNodeToVariant(&list->values[i]));
    return result;
}

QVariant mpvNodeToVariant(mpv_node *node)
{
    if (!node)
        return {};
    switch (node->format) {
    case MPV_FORMAT_STRING:
        return QString::fromUtf8(node->u.string);
    case MPV_FORMAT_FLAG:
        return node->u.flag != 0;
    case MPV_FORMAT_INT64:
        return static_cast<qlonglong>(node->u.int64);
    case MPV_FORMAT_DOUBLE:
        return node->u.double_;
    case MPV_FORMAT_NODE_ARRAY:
        return mpvNodeListToVariant(node->u.list);
    case MPV_FORMAT_NODE_MAP:
        return mpvNodeMapToVariant(node->u.list);
    default:
        return {};
    }
}

// Builds a QVariantList the caller passed (e.g. ["loadfile", path, "replace"])
// into an array of char* for mpv_command, the simple string-args form that
// covers everything Prism's command surface needs.
class MpvCommandArgs {
public:
    explicit MpvCommandArgs(const QVariantList &params)
    {
        m_strings.reserve(params.size());
        for (const QVariant &v : params)
            m_strings.append(v.toString().toUtf8());
        m_args.reserve(m_strings.size() + 1);
        for (QByteArray &s : m_strings)
            m_args.append(s.data());
        m_args.append(nullptr);
    }
    const char **data() { return m_args.data(); }

private:
    QList<QByteArray> m_strings;
    QList<const char *> m_args;
};

} // namespace

class MpvRenderer : public QQuickFramebufferObject::Renderer {
public:
    explicit MpvRenderer(MpvObject *obj) : m_obj(obj) {}

    ~MpvRenderer() override
    {
        if (m_mpvGl)
            mpv_render_context_free(m_mpvGl);
    }

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        if (!m_mpvGl)
            initMpvGl();
        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override
    {
        if (!m_mpvGl)
            return;

        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo mpfbo;
        mpfbo.fbo = static_cast<int>(fbo->handle());
        mpfbo.w = fbo->width();
        mpfbo.h = fbo->height();
        mpfbo.internal_format = 0;

        // QQuickFramebufferObject already accounts for the GL texture's
        // bottom-left origin when compositing into the scene graph, so
        // telling mpv to also flip (flipY=1) double-flips the image -
        // this is what produced a 180-degree-rotated/mirrored picture.
        int flipY = 0;
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_INVALID, nullptr}
        };
        mpv_render_context_render(m_mpvGl, params);
    }

private:
    void initMpvGl()
    {
        mpv_opengl_init_params glInit{getProcAddressMpv, nullptr};
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
            {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit},
            {MPV_RENDER_PARAM_INVALID, nullptr}
        };
        if (mpv_render_context_create(&m_mpvGl, m_obj->handle(), params) < 0) {
            qWarning() << "Prism: failed to create mpv render context";
            m_mpvGl = nullptr;
            return;
        }
        mpv_render_context_set_update_callback(
            m_mpvGl,
            [](void *ctx) {
                auto *self = static_cast<MpvObject *>(ctx);
                // update() on the item itself, not just the window - this
                // is what actually marks this FBO item dirty so the scene
                // graph re-invokes render() for the new frame. Calling
                // window()->update() alone let stale frames linger when
                // switching files (audio advanced, picture did not).
                QMetaObject::invokeMethod(self, [self]() {
                    self->update();
                }, Qt::QueuedConnection);
            },
            m_obj);
    }

    MpvObject *m_obj;
    mpv_render_context *m_mpvGl = nullptr;
};

MpvObject::MpvObject(QQuickItem *parent)
    : QQuickFramebufferObject(parent)
{
    m_mpv = mpv_create();
    if (!m_mpv) {
        m_engineState = QStringLiteral("error");
        m_engineError = QStringLiteral("mpv_create failed.");
        return;
    }

    // Behavior flags matched to the Phase 1 plan: idle so the engine
    // stays alive with nothing loaded, hardware decode auto-safe,
    // D3D11-capable render path via gpu-next.
    mpv_set_option_string(m_mpv, "config", "no");
    mpv_set_option_string(m_mpv, "idle", "yes");
    mpv_set_option_string(m_mpv, "vo", "libmpv");
    mpv_set_option_string(m_mpv, "hwdec", "auto-safe");
    mpv_set_option_string(m_mpv, "keep-open", "yes");
    mpv_set_option_string(m_mpv, "terminal", "no");
    mpv_set_option_string(m_mpv, "ytdl", "no");
    mpv_set_option_string(m_mpv, "osc", "no");

    if (mpv_initialize(m_mpv) < 0) {
        m_engineState = QStringLiteral("error");
        m_engineError = QStringLiteral("mpv_initialize failed.");
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
        return;
    }

    observeProperties();

    mpv_set_wakeup_callback(m_mpv, &MpvObject::onMpvEventsStatic, this);

    m_engineState = QStringLiteral("ready");
    setFlag(QQuickItem::ItemHasContents);
}

MpvObject::~MpvObject()
{
    if (m_mpv)
        mpv_terminate_destroy(m_mpv);
}

QQuickFramebufferObject::Renderer *MpvObject::createRenderer() const
{
    return new MpvRenderer(const_cast<MpvObject *>(this));
}

void MpvObject::observeProperties()
{
    mpv_observe_property(m_mpv, 0, "path", MPV_FORMAT_STRING);
    mpv_observe_property(m_mpv, 0, "media-title", MPV_FORMAT_STRING);
    mpv_observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "volume", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "hwdec-current", MPV_FORMAT_STRING);
    mpv_observe_property(m_mpv, 0, "track-list", MPV_FORMAT_NODE);
    mpv_observe_property(m_mpv, 0, "width", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "height", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "eof-reached", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "sid", MPV_FORMAT_NODE);
    mpv_observe_property(m_mpv, 0, "brightness", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "contrast", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "saturation", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "gamma", MPV_FORMAT_INT64);
}

void MpvObject::onMpvEventsStatic(void *ctx)
{
    auto *self = static_cast<MpvObject *>(ctx);
    QMetaObject::invokeMethod(self, "onMpvEvents", Qt::QueuedConnection);
}

void MpvObject::onMpvEvents()
{
    if (!m_mpv)
        return;
    while (true) {
        mpv_event *event = mpv_wait_event(m_mpv, 0);
        if (event->event_id == MPV_EVENT_NONE)
            break;
        handleEvent(event);
    }
}

void MpvObject::handleEvent(void *eventPtr)
{
    auto *event = static_cast<mpv_event *>(eventPtr);

    switch (event->event_id) {
    case MPV_EVENT_PROPERTY_CHANGE: {
        auto *prop = static_cast<mpv_event_property *>(event->data);
        const QString name = QString::fromUtf8(prop->name);

        if (name == "path" && prop->format == MPV_FORMAT_STRING) {
            m_mediaPath = QString::fromUtf8(*static_cast<char **>(prop->data));
            emit mediaPathChanged();
        } else if (name == "media-title" && prop->format == MPV_FORMAT_STRING) {
            m_mediaTitle = QString::fromUtf8(*static_cast<char **>(prop->data));
            emit mediaTitleChanged();
        } else if (name == "time-pos" && prop->format == MPV_FORMAT_DOUBLE) {
            m_position = *static_cast<double *>(prop->data);
            emit positionChanged();
        } else if (name == "duration" && prop->format == MPV_FORMAT_DOUBLE) {
            m_duration = *static_cast<double *>(prop->data);
            emit durationChanged();
        } else if (name == "pause" && prop->format == MPV_FORMAT_FLAG) {
            m_paused = *static_cast<int *>(prop->data) != 0;
            emit pausedChanged();
        } else if (name == "volume" && prop->format == MPV_FORMAT_INT64) {
            m_volume = static_cast<int>(*static_cast<int64_t *>(prop->data));
            emit volumeChanged();
        } else if (name == "speed" && prop->format == MPV_FORMAT_DOUBLE) {
            m_speed = *static_cast<double *>(prop->data);
            emit speedChanged();
        } else if (name == "hwdec-current" && prop->format == MPV_FORMAT_STRING) {
            m_hwdecCurrent = QString::fromUtf8(*static_cast<char **>(prop->data));
            emit hwdecCurrentChanged();
        } else if (name == "track-list" && prop->format == MPV_FORMAT_NODE) {
            auto *node = static_cast<mpv_node *>(prop->data);
            m_trackList = mpvNodeToVariant(node).toList();
            emit trackListChanged();
        } else if (name == "width" && prop->format == MPV_FORMAT_INT64) {
            m_videoWidth = static_cast<int>(*static_cast<int64_t *>(prop->data));
            emit videoParamsChanged();
        } else if (name == "height" && prop->format == MPV_FORMAT_INT64) {
            m_videoHeight = static_cast<int>(*static_cast<int64_t *>(prop->data));
            emit videoParamsChanged();
        } else if (name == "sid" && prop->format == MPV_FORMAT_NODE) {
            auto *node = static_cast<mpv_node *>(prop->data);
            const QVariant v = mpvNodeToVariant(node);
            // sid is "no" (string) when off, or a numeric track id when a
            // subtitle track is selected.
            const bool active = v.typeId() != QMetaType::QString || v.toString() != QStringLiteral("no");
            if (active != m_sidActive) {
                m_sidActive = active;
                emit sidActiveChanged();
            }
        } else if (name == "brightness" && prop->format == MPV_FORMAT_INT64) {
            m_brightness = static_cast<int>(*static_cast<int64_t *>(prop->data));
            emit brightnessChanged();
        } else if (name == "contrast" && prop->format == MPV_FORMAT_INT64) {
            m_contrast = static_cast<int>(*static_cast<int64_t *>(prop->data));
            emit contrastChanged();
        } else if (name == "saturation" && prop->format == MPV_FORMAT_INT64) {
            m_saturation = static_cast<int>(*static_cast<int64_t *>(prop->data));
            emit saturationChanged();
        } else if (name == "gamma" && prop->format == MPV_FORMAT_INT64) {
            m_gamma = static_cast<int>(*static_cast<int64_t *>(prop->data));
            emit gammaChanged();
        } else if (name == "eof-reached" && prop->format == MPV_FORMAT_FLAG) {
            // The authoritative "this file is genuinely done" signal.
            // MPV_EVENT_END_FILE's reason string is not reliable with
            // keep-open=yes (it reported "stop" instead of "eof" here,
            // which silently broke playlist auto-advance).
            m_eofReached = *static_cast<int *>(prop->data) != 0;
            emit eofReachedChanged();
        }
        break;
    }
    case MPV_EVENT_FILE_LOADED:
        emit fileLoaded();
        break;
    case MPV_EVENT_END_FILE: {
        auto *endFile = static_cast<mpv_event_end_file *>(event->data);
        QString reason = QStringLiteral("unknown");
        switch (endFile->reason) {
        case MPV_END_FILE_REASON_EOF: reason = QStringLiteral("eof"); break;
        case MPV_END_FILE_REASON_STOP: reason = QStringLiteral("stop"); break;
        case MPV_END_FILE_REASON_QUIT: reason = QStringLiteral("quit"); break;
        case MPV_END_FILE_REASON_ERROR: reason = QStringLiteral("error"); break;
        case MPV_END_FILE_REASON_REDIRECT: reason = QStringLiteral("redirect"); break;
        default: break;
        }
        emit endOfFile(reason);
        break;
    }
    default:
        break;
    }
}

void MpvObject::command(const QVariant &params)
{
    if (!m_mpv)
        return;
    MpvCommandArgs args(params.toList());
    mpv_command_async(m_mpv, 0, args.data());
}

void MpvObject::setProperty(const QString &name, const QVariant &value)
{
    if (!m_mpv)
        return;

    const QByteArray nameUtf8 = name.toUtf8();

    switch (value.typeId()) {
    case QMetaType::Bool: {
        int flag = value.toBool() ? 1 : 0;
        mpv_set_property(m_mpv, nameUtf8.constData(), MPV_FORMAT_FLAG, &flag);
        break;
    }
    case QMetaType::Int:
    case QMetaType::LongLong: {
        int64_t v = value.toLongLong();
        mpv_set_property(m_mpv, nameUtf8.constData(), MPV_FORMAT_INT64, &v);
        break;
    }
    case QMetaType::Double: {
        double v = value.toDouble();
        mpv_set_property(m_mpv, nameUtf8.constData(), MPV_FORMAT_DOUBLE, &v);
        break;
    }
    default: {
        QByteArray strVal = value.toString().toUtf8();
        const char *v = strVal.constData();
        mpv_set_property(m_mpv, nameUtf8.constData(), MPV_FORMAT_STRING, &v);
        break;
    }
    }
}

QVariant MpvObject::getProperty(const QString &name) const
{
    if (!m_mpv)
        return {};
    char *result = nullptr;
    if (mpv_get_property(m_mpv, name.toUtf8().constData(), MPV_FORMAT_STRING, &result) >= 0) {
        QString str = QString::fromUtf8(result);
        mpv_free(result);
        return str;
    }
    return {};
}

QString MpvObject::takeScreenshot(const QString &filePath)
{
    if (!m_mpv)
        return QStringLiteral("Playback engine unavailable.");

    QByteArray pathUtf8 = filePath.toUtf8();
    const char *args[] = {"screenshot-to-file", pathUtf8.constData(), "video", nullptr};
    int result = mpv_command(m_mpv, args);
    if (result < 0)
        return QString::fromUtf8(mpv_error_string(result));
    return QString(); // empty = success
}

void MpvObject::loadFile(const QString &path, bool append)
{
    if (!m_mpv)
        return;
    QByteArray pathUtf8 = path.toUtf8();
    const char *mode = append ? "append-play" : "replace";
    const char *args[] = {"loadfile", pathUtf8.constData(), mode, nullptr};
    mpv_command_async(m_mpv, 0, args);
}
