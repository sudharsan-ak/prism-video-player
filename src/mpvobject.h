#pragma once

#include <QQuickFramebufferObject>
#include <QObject>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

struct mpv_handle;
struct mpv_render_context;

// Embeds mpv as a QQuickFramebufferObject, so its decoded frames render
// into a normal Qt Quick scene-graph item instead of a separate native
// HWND. This is what makes right-click, hover, and overlay QML items
// over the video work like any other part of the UI (the Electron
// build's "separate native window" approach could not do this).
class MpvObject : public QQuickFramebufferObject {
    Q_OBJECT
    Q_PROPERTY(QString mediaPath READ mediaPath NOTIFY mediaPathChanged)
    Q_PROPERTY(QString mediaTitle READ mediaTitle NOTIFY mediaTitleChanged)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY pausedChanged)
    Q_PROPERTY(int volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(double speed READ speed NOTIFY speedChanged)
    Q_PROPERTY(QString hwdecCurrent READ hwdecCurrent NOTIFY hwdecCurrentChanged)
    Q_PROPERTY(QVariantList trackList READ trackList NOTIFY trackListChanged)
    Q_PROPERTY(int videoWidth READ videoWidth NOTIFY videoParamsChanged)
    Q_PROPERTY(int videoHeight READ videoHeight NOTIFY videoParamsChanged)
    Q_PROPERTY(QString engineState READ engineState NOTIFY engineStateChanged)
    Q_PROPERTY(QString engineError READ engineError NOTIFY engineStateChanged)
    Q_PROPERTY(bool eofReached READ eofReached NOTIFY eofReachedChanged)
    Q_PROPERTY(bool sidActive READ sidActive NOTIFY sidActiveChanged)
    Q_PROPERTY(int brightness READ brightness NOTIFY brightnessChanged)
    Q_PROPERTY(int contrast READ contrast NOTIFY contrastChanged)
    Q_PROPERTY(int saturation READ saturation NOTIFY saturationChanged)
    Q_PROPERTY(int gamma READ gamma NOTIFY gammaChanged)

public:
    explicit MpvObject(QQuickItem *parent = nullptr);
    ~MpvObject() override;

    Renderer *createRenderer() const override;

    QString mediaPath() const { return m_mediaPath; }
    QString mediaTitle() const { return m_mediaTitle; }
    double position() const { return m_position; }
    double duration() const { return m_duration; }
    bool paused() const { return m_paused; }
    int volume() const { return m_volume; }
    double speed() const { return m_speed; }
    QString hwdecCurrent() const { return m_hwdecCurrent; }
    QVariantList trackList() const { return m_trackList; }
    int videoWidth() const { return m_videoWidth; }
    int videoHeight() const { return m_videoHeight; }
    QString engineState() const { return m_engineState; }
    QString engineError() const { return m_engineError; }
    bool eofReached() const { return m_eofReached; }
    bool sidActive() const { return m_sidActive; }
    int brightness() const { return m_brightness; }
    int contrast() const { return m_contrast; }
    int saturation() const { return m_saturation; }
    int gamma() const { return m_gamma; }

    mpv_handle *handle() const { return m_mpv; }

public slots:
    // Thin wrappers so QML can drive mpv without touching the C API directly.
    void command(const QVariant &params);
    void setProperty(const QString &name, const QVariant &value);
    QVariant getProperty(const QString &name) const;
    void loadFile(const QString &path, bool append = false);
    // Synchronous (not fire-and-forget like command()) so a failure -
    // bad path, no permission, no frame decoded yet - is reported
    // immediately instead of silently vanishing, which is what made the
    // screenshot button look like it "did nothing" on failure.
    QString takeScreenshot(const QString &filePath);

signals:
    void mediaPathChanged();
    void mediaTitleChanged();
    void positionChanged();
    void durationChanged();
    void pausedChanged();
    void volumeChanged();
    void speedChanged();
    void hwdecCurrentChanged();
    void trackListChanged();
    void videoParamsChanged();
    void engineStateChanged();
    void eofReachedChanged();
    void sidActiveChanged();
    void brightnessChanged();
    void contrastChanged();
    void saturationChanged();
    void gammaChanged();
    void fileLoaded();
    void endOfFile(const QString &reason);
    void mpvEvent(const QString &eventName);

private slots:
    void onMpvEvents();

private:
    static void onMpvEventsStatic(void *ctx);
    void handleEvent(void *event);
    void observeProperties();

    mpv_handle *m_mpv = nullptr;

    QString m_mediaPath;
    QString m_mediaTitle;
    double m_position = 0.0;
    double m_duration = 0.0;
    bool m_paused = false;
    int m_volume = 80;
    double m_speed = 1.0;
    QString m_hwdecCurrent;
    QVariantList m_trackList;
    int m_videoWidth = 0;
    int m_videoHeight = 0;
    QString m_engineState = QStringLiteral("starting");
    QString m_engineError;
    bool m_eofReached = false;
    bool m_sidActive = false;
    int m_brightness = 0;
    int m_contrast = 0;
    int m_saturation = 0;
    int m_gamma = 0;

    friend class MpvRenderer;
};
