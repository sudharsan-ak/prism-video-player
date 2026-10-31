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
constexpr int MaxConcurrentJobs = 2;
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
    for (QProcess *p : m_processes) {
        p->disconnect(this);
        p->kill();
        p->deleteLater();
    }
    m_processes.clear();
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
    const QString resolvedPath = info.canonicalFilePath();
    const bool reuse = m_cachedSource == resolvedPath &&
                       m_cachedSize == info.size() &&
                       m_cachedModified == info.lastModified() &&
                       m_cachedFrames.size() == ThumbnailCount;
    if (!reuse) {
        m_cachedSource = resolvedPath;
        m_cachedSize = info.size();
        m_cachedModified = info.lastModified();
        m_cachedFrames = QStringList();
        for (int i = 0; i < ThumbnailCount; ++i)
            m_cachedFrames.append(QString());
    }
    m_frames = m_cachedFrames;
    m_source = info.absoluteFilePath();
    m_duration = duration;
    m_index = 0;
    m_generating = true;
    emit framesChanged();
    emit stateChanged();
    QMetaObject::invokeMethod(this, [this] { launchNext(); }, Qt::QueuedConnection);
}

void VideoThumbnailController::launchNext()
{
    if (!m_generating)
        return;
    while (m_processes.size() < MaxConcurrentJobs && m_index < ThumbnailCount) {
        const int index = m_index++;
        if (!m_frames[index].isEmpty())
            continue; // Already cached for this unchanged local file.
        const quint64 job = m_generation;
        const QString target = m_cache.filePath(
            QStringLiteral("thumb-%1-%2.jpg").arg(job).arg(index));
        const double timestamp = qMax(0.0, qMin(m_duration - 0.001,
            (index + 0.5) * m_duration / ThumbnailCount));

        QProcess *proc = new QProcess(this);
        m_processes.append(proc);
        connect(proc, &QProcess::finished, this,
                [this, proc, index, job, target](int exitCode, QProcess::ExitStatus status) {
            if (job != m_generation)
                return;
            m_processes.removeAll(proc);
            proc->deleteLater();
            if (status == QProcess::NormalExit && exitCode == 0 &&
                QFileInfo(target).isFile() && QFileInfo(target).size() > 0) {
                const QString url = QUrl::fromLocalFile(target).toString();
                m_frames[index] = url;
                m_cachedFrames[index] = url;
                emit framesChanged();
            }
            launchNext();
        });
        connect(proc, &QProcess::errorOccurred, this,
                [this, proc, job](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart && job == m_generation) {
                m_processes.removeAll(proc);
                proc->deleteLater();
                m_error = QStringLiteral("FFmpeg could not start for thumbnail extraction.");
                m_generating = false;
                emit stateChanged();
            }
        });
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
            QStringLiteral("-q:v"), QStringLiteral("5"),
            QStringLiteral("-y"), target
        });
    }
    if (m_processes.isEmpty() && m_index >= ThumbnailCount) {
        m_generating = false;
        emit stateChanged();
    }
}
