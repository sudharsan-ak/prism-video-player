#include "videothumbnailcontroller.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QMetaObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QtGlobal>
#include <cmath>

namespace {
constexpr int ThumbnailCount = 16;
}

VideoThumbnailController::VideoThumbnailController(QObject *parent) : QObject(parent) {}

QString VideoThumbnailController::ffmpegExecutable() const
{
    const QString adjacent = QCoreApplication::applicationDirPath() + QStringLiteral("/ffmpeg.exe");
    if (QFileInfo(adjacent).isFile() && QFileInfo(adjacent).isExecutable())
        return adjacent;
    return QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
}

void VideoThumbnailController::stop()
{
    ++m_generation;
    if (m_process) {
        m_process->disconnect(this);
        m_process->kill();
        m_process->deleteLater();
        m_process = nullptr;
    }
    m_generating = false;
    m_index = 0;
    m_source.clear();
    m_frames.clear();
    m_error.clear();
    emit framesChanged();
    emit stateChanged();
}

void VideoThumbnailController::generate(const QString &source, double duration)
{
    stop();
    const QFileInfo info(source);
    if (!info.isFile() || !info.isReadable() || !info.isAbsolute() ||
        source.startsWith(QStringLiteral("\\\\")) || source.startsWith(QStringLiteral("//")) ||
        QRegularExpression(QStringLiteral("^[a-zA-Z][a-zA-Z0-9+.-]*://")).match(source).hasMatch() ||
        !std::isfinite(duration) || duration <= 0) {
        m_error = QStringLiteral("No local video available for thumbnails.");
        emit stateChanged();
        return;
    }
    m_program = ffmpegExecutable();
    if (m_program.isEmpty()) {
        m_error = QStringLiteral("FFmpeg is required for thumbnail previews.");
        emit stateChanged();
        return;
    }
    if (!m_cache.isValid()) {
        m_error = QStringLiteral("Cannot create temporary thumbnail cache.");
        emit stateChanged();
        return;
    }
    m_source = info.absoluteFilePath();
    m_duration = duration;
    m_frames = QStringList();
    for (int i = 0; i < ThumbnailCount; ++i)
        m_frames.append(QString());
    m_generating = true;
    emit framesChanged();
    emit stateChanged();
    QMetaObject::invokeMethod(this, [this] { launchNext(); }, Qt::QueuedConnection);
}

void VideoThumbnailController::launchNext()
{
    if (!m_generating || m_process)
        return;
    if (m_index >= ThumbnailCount) {
        m_generating = false;
        emit stateChanged();
        return;
    }
    const int index = m_index++;
    const quint64 job = m_generation;
    const QString target = m_cache.filePath(QStringLiteral("thumb-%1-%2.jpg").arg(job).arg(index));
    // Sample the middle of each time slice. Accurate-enough seeking before
    // -i keeps thumbnail generation fast even for long videos.
    const double timestamp = qMax(0.0, qMin(m_duration - 0.001,
        (index + 0.5) * m_duration / ThumbnailCount));

    QProcess *proc = new QProcess(this);
    m_process = proc;
    connect(proc, &QProcess::finished, this,
            [this, proc, index, job, target](int exitCode, QProcess::ExitStatus status) {
        if (job != m_generation || proc != m_process)
            return;
        m_process = nullptr;
        proc->deleteLater();
        if (status == QProcess::NormalExit && exitCode == 0 &&
            QFileInfo(target).isFile() && QFileInfo(target).size() > 0) {
            m_frames[index] = QUrl::fromLocalFile(target).toString();
            emit framesChanged();
        }
        // Continue even if one frame cannot be decoded.
        QMetaObject::invokeMethod(this, [this] { launchNext(); }, Qt::QueuedConnection);
    });
    connect(proc, &QProcess::errorOccurred, this,
            [this, proc, job](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart && job == m_generation && proc == m_process) {
            m_error = QStringLiteral("FFmpeg could not start to generate thumbnails.");
            m_generating = false;
            m_process = nullptr;
            proc->deleteLater();
            emit stateChanged();
        }
    });
    // Bound individual extraction time so corrupt media cannot hang the UI.
    QTimer::singleShot(10000, proc, [proc] {
        if (proc->state() != QProcess::NotRunning)
            proc->kill();
    });

    proc->start(m_program, {
        QStringLiteral("-hide_banner"), QStringLiteral("-nostdin"),
        QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-ss"), QString::number(timestamp, 'f', 3),
        QStringLiteral("-protocol_whitelist"), QStringLiteral("file,crypto,data"),
        QStringLiteral("-i"), m_source,
        QStringLiteral("-map"), QStringLiteral("0:V:0"),
        QStringLiteral("-frames:v"), QStringLiteral("1"),
        QStringLiteral("-vf"),
        QStringLiteral("scale=160:90:force_original_aspect_ratio=increase,crop=160:90"),
        QStringLiteral("-q:v"), QStringLiteral("4"),
        QStringLiteral("-y"), target
    });
}
