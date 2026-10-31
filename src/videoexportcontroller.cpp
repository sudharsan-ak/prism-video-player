#include "videoexportcontroller.h"
#include "settingsstore.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#ifdef Q_OS_WIN
#include <windows.h>
#endif
#include <QUuid>
#include <QtGlobal>
#include <cmath>

namespace {
bool isLocalAbsolutePath(const QString &path)
{
    if (path.isEmpty() || path.contains(QChar('\0')) ||
        path.startsWith(QStringLiteral("\\\\")) || path.startsWith(QStringLiteral("//")))
        return false;
    if (QRegularExpression(QStringLiteral("^[a-zA-Z][a-zA-Z0-9+.-]*://")).match(path).hasMatch())
        return false;
    return QFileInfo(path).isAbsolute();
}
}

VideoExportController::VideoExportController(SettingsStore *settings, QObject *parent)
    : QObject(parent), m_settings(settings)
{
    connect(&m_process, &QProcess::readyReadStandardOutput, this, [this] {
        parseProgress(m_process.readAllStandardOutput());
    });
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        m_lastStderr = (m_lastStderr + QString::fromLocal8Bit(m_process.readAllStandardError())).right(3000);
    });
    connect(&m_process, &QProcess::finished, this, &VideoExportController::finished);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        // QProcess::finished is not guaranteed for a failure to start.
        if (error == QProcess::FailedToStart && m_busy) {
            fail(QStringLiteral("Could not start FFmpeg: %1").arg(m_process.errorString()));
        }
    });
}

QString VideoExportController::ffmpegExecutable() const
{
    const QString adjacent = QCoreApplication::applicationDirPath() + QStringLiteral("/ffmpeg.exe");
    const QFileInfo adjacentFile(adjacent);
    if (adjacentFile.isFile() && adjacentFile.isExecutable())
        return adjacent;
    return QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
}

QUrl VideoExportController::suggestedOutputUrl(const QString &sourcePath) const
{
    const QFileInfo info(sourcePath);
    const QString basename = info.completeBaseName().isEmpty()
        ? QStringLiteral("Prism-video") : info.completeBaseName();
    const QString folder = info.isFile() ? info.absolutePath()
        : QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    QString path = QDir(folder).filePath(basename + QStringLiteral("-trimmed.mp4"));
    for (int n = 2; QFileInfo::exists(path); ++n) {
        path = QDir(folder).filePath(basename + QStringLiteral("-trimmed-%1.mp4").arg(n));
    }
    return QUrl::fromLocalFile(path);
}

bool VideoExportController::startTrim(const QString &sourcePath, double startSeconds,
                                      double endSeconds, const QUrl &destination,
                                      double playbackSpeed)
{
    return beginTrim(sourcePath, startSeconds, endSeconds, destination, false, playbackSpeed);
}

bool VideoExportController::startReplaceTrim(const QString &sourcePath,
                                            double startSeconds, double endSeconds,
                                            double playbackSpeed)
{
    return beginTrim(sourcePath, startSeconds, endSeconds,
                     QUrl::fromLocalFile(sourcePath), true, playbackSpeed);
}

bool VideoExportController::beginTrim(const QString &sourcePath, double startSeconds,
                                      double endSeconds, const QUrl &destination,
                                      bool replaceOriginal, double playbackSpeed)
{
    if (m_busy)
        return false;

    m_error.clear();
    m_lastOutput = {};
    m_backupPath.clear();
    m_lastWasReplacement = false;
    m_replacePending = false;
    m_replaceOriginal = false;
    m_status.clear();
    emit stateChanged();

    const QFileInfo source(sourcePath);
    const QString outputPath = QDir::cleanPath(destination.toLocalFile());
    const QFileInfo output(outputPath);
    if (!isLocalAbsolutePath(sourcePath) || !source.isFile() || !source.isReadable() ||
        !destination.isLocalFile() || !isLocalAbsolutePath(outputPath) ||
        output.suffix().compare(QStringLiteral("mp4"), Qt::CaseInsensitive) != 0) {
        fail(QStringLiteral("Choose an existing local video and a local .mp4 destination."));
        return false;
    }
    if (!std::isfinite(playbackSpeed) || playbackSpeed < 0.25 || playbackSpeed > 2.0) {
        fail(QStringLiteral("Select a playback speed from 0.25x to 2.0x."));
        return false;
    }
    if (!std::isfinite(startSeconds) || !std::isfinite(endSeconds) ||
        startSeconds < 0.0 || endSeconds - startSeconds < 0.1) {
        fail(QStringLiteral("Trim end must be at least 0.1 seconds after the start."));
        return false;
    }
    const QString inputCanonical = source.canonicalFilePath();
    const bool sameFile = inputCanonical.compare(output.absoluteFilePath(), Qt::CaseInsensitive) == 0;
    if (replaceOriginal) {
        // Never put newly encoded MP4 data under a non-MP4 file extension.
        if (!sameFile || source.isSymLink() ||
            source.suffix().compare(QStringLiteral("mp4"), Qt::CaseInsensitive) != 0) {
            fail(QStringLiteral("Replace original is supported only for ordinary local MP4 files."));
            return false;
        }
    } else if (sameFile || output.exists()) {
        fail(QStringLiteral("Choose a new filename. Copy export never overwrites existing files."));
        return false;
    }
    const QFileInfo folder(output.absolutePath());
    if (!folder.isDir() || !folder.isWritable()) {
        fail(QStringLiteral("The selected destination folder is not writable."));
        return false;
    }

    const QString program = ffmpegExecutable();
    if (program.isEmpty()) {
        fail(QStringLiteral("FFmpeg was not found. Put ffmpeg.exe next to Prism.exe or add FFmpeg to PATH."));
        return false;
    }

    // Render to a random same-directory temporary .mp4 and rename only on
    // success. FFmpeg never touches the input or the selected final path.
    m_pendingOutput = output.absoluteFilePath();
    m_pendingSource = source.absoluteFilePath();
    m_sourceSize = source.size();
    m_sourceModified = source.lastModified();
    m_replaceOriginal = replaceOriginal;
    m_playbackSpeed = playbackSpeed;
    m_keepBackupForJob = m_settings && m_settings->keepBackupOnReplace();
    m_temporaryOutput = QDir(output.absolutePath()).filePath(
        QStringLiteral(".prism-export-%1.mp4").arg(QUuid::createUuid().toString(QUuid::WithoutBraces)));
    const double sourceDuration = endSeconds - startSeconds;
    m_clipDuration = sourceDuration / playbackSpeed;
    m_progress = 0.0;
    m_progressBuffer.clear();
    m_lastStderr.clear();
    m_cancelRequested = false;
    m_busy = true;
    m_status = replaceOriginal
        ? QStringLiteral("Encoding before safely replacing original...")
        : QStringLiteral("Encoding trimmed copy...");
    emit progressChanged();
    emit stateChanged();

    // Accurate cuts and speed changes require re-encoding. Video PTS and
    // audio tempo are adjusted together to keep A/V in sync. atempo
    // supports 0.5..2.0 directly, so chain two 0.5 filters for 0.25x.
    const QString speed = QString::number(playbackSpeed, 'f', 3);
    const QString videoFilter = QStringLiteral("setpts=(PTS-STARTPTS)/") + speed;
    const QString audioFilter = playbackSpeed < 0.5
        ? QStringLiteral("atempo=0.5,atempo=") + QString::number(playbackSpeed / 0.5, 'f', 3)
        : QStringLiteral("atempo=") + speed;
    // FFmpeg receives separate argv elements, never a shell command.
    const QStringList args = {
        QStringLiteral("-hide_banner"), QStringLiteral("-nostdin"),
        QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-stats_period"), QStringLiteral("0.25"),
        QStringLiteral("-progress"), QStringLiteral("pipe:1"),
        QStringLiteral("-n"), QStringLiteral("-ss"), QString::number(startSeconds, 'f', 3),
        QStringLiteral("-t"), QString::number(sourceDuration, 'f', 3),
        QStringLiteral("-protocol_whitelist"), QStringLiteral("file,crypto,data"),
        QStringLiteral("-i"), source.absoluteFilePath(),
        QStringLiteral("-map"), QStringLiteral("0:V:0"),
        QStringLiteral("-map"), QStringLiteral("0:a:0?"),
        QStringLiteral("-c:v"), QStringLiteral("libx264"),
        QStringLiteral("-preset"), m_settings ? m_settings->encodingPreset() : QStringLiteral("veryfast"),
        QStringLiteral("-crf"), QStringLiteral("18"),
        QStringLiteral("-vf"), videoFilter,
        QStringLiteral("-af"), audioFilter,
        QStringLiteral("-pix_fmt"), QStringLiteral("yuv420p"),
        QStringLiteral("-c:a"), QStringLiteral("aac"),
        QStringLiteral("-b:a"), QStringLiteral("192k"),
        QStringLiteral("-movflags"), QStringLiteral("+faststart"),
        QStringLiteral("-f"), QStringLiteral("mp4"), m_temporaryOutput
    };
    m_process.setProgram(program);
    m_process.setArguments(args);
    m_process.start(QIODevice::ReadOnly);
    return true;
}

void VideoExportController::parseProgress(const QByteArray &chunk)
{
    m_progressBuffer.append(chunk);
    int newline = -1;
    while ((newline = m_progressBuffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_progressBuffer.left(newline).trimmed();
        m_progressBuffer.remove(0, newline + 1);
        if (!line.startsWith("out_time="))
            continue;
        const QList<QByteArray> parts = line.mid(9).split(':');
        if (parts.size() != 3)
            continue;
        bool okH = false, okM = false, okS = false;
        const double h = parts[0].toDouble(&okH);
        const double m = parts[1].toDouble(&okM);
        const double s = parts[2].toDouble(&okS);
        if (!okH || !okM || !okS || m_clipDuration <= 0.0)
            continue;
        const double next = qBound(0.0, (h * 3600.0 + m * 60.0 + s) / m_clipDuration, 0.99);
        if (next > m_progress) {
            m_progress = next;
            emit progressChanged();
        }
    }
}

void VideoExportController::finished(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (!m_busy)
        return;
    // Drain the final pipe output before reporting completion.
    parseProgress(m_process.readAllStandardOutput());
    m_lastStderr += QString::fromLocal8Bit(m_process.readAllStandardError());

    if (m_cancelRequested) {
        QFile::remove(m_temporaryOutput);
        m_busy = false;
        m_status = QStringLiteral("Export canceled.");
        m_error.clear();
        emit stateChanged();
        return;
    }
    if (exitStatus != QProcess::NormalExit || exitCode != 0 ||
        !QFileInfo(m_temporaryOutput).isFile() || QFileInfo(m_temporaryOutput).size() == 0) {
        const QString detail = m_lastStderr.trimmed().right(900);
        fail(detail.isEmpty() ? QStringLiteral("FFmpeg could not export this video.")
                              : QStringLiteral("FFmpeg export failed: %1").arg(detail));
        return;
    }
    if (m_replaceOriginal) {
        m_replacePending = true;
        m_status = QStringLiteral("Encoding complete. Releasing original video...");
        emit stateChanged();
        emit replacementPrepared();
        return;
    }
    if (QFileInfo::exists(m_pendingOutput) || !QFile::rename(m_temporaryOutput, m_pendingOutput)) {
        fail(QStringLiteral("Could not save the edited video. Check the folder and output name."));
        return;
    }
    markCompleted(m_pendingOutput, false);
}


void VideoExportController::markCompleted(const QString &outputPath, bool replaced)
{
    m_lastOutput = QUrl::fromLocalFile(outputPath);
    m_lastWasReplacement = replaced;
    m_progress = 1.0;
    m_busy = false;
    m_replacePending = false;
    m_status = replaced
        ? (m_keepBackupForJob ? QStringLiteral("Original replaced. Backup saved.")
                              : QStringLiteral("Original replaced. No backup requested."))
        : QStringLiteral("Edited MP4 saved.");
    m_error.clear();
    m_temporaryOutput.clear();
    emit progressChanged();
    emit stateChanged();
    emit completed(m_lastOutput);
}

void VideoExportController::completeReplacement()
{
    if (!m_busy || !m_replacePending)
        return;
    // mpv's stop is asynchronous; wait for its input handle to close.
    QTimer::singleShot(450, this, [this] { finalizeReplacement(0); });
}

void VideoExportController::finalizeReplacement(int attempt)
{
    if (!m_busy || !m_replacePending || m_cancelRequested)
        return;
    const QFileInfo source(m_pendingSource);
    if (!source.isFile() || source.size() != m_sourceSize ||
        source.lastModified() != m_sourceModified) {
        saveFallbackCopy(QStringLiteral("The original changed during export."));
        return;
    }
#ifdef Q_OS_WIN
    if (m_keepBackupForJob && m_backupPath.isEmpty()) {
        const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
        const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
        m_backupPath = QDir(source.absolutePath()).filePath(
            source.completeBaseName() + QStringLiteral("-prism-backup-") + stamp
            + QStringLiteral("-") + id + QStringLiteral(".mp4"));
    }
    // Atomically replace when possible. Optional backup remains explicit.
    const BOOL ok = ReplaceFileW(
        reinterpret_cast<LPCWSTR>(m_pendingSource.utf16()),
        reinterpret_cast<LPCWSTR>(m_temporaryOutput.utf16()),
        m_keepBackupForJob ? reinterpret_cast<LPCWSTR>(m_backupPath.utf16()) : nullptr,
        REPLACEFILE_IGNORE_MERGE_ERRORS, nullptr, nullptr);
    if (ok) {
        markCompleted(m_pendingSource, true);
        return;
    }
    const DWORD err = GetLastError();
    if (attempt < 8) {
        QTimer::singleShot(300, this, [this, attempt] { finalizeReplacement(attempt + 1); });
        return;
    }
    saveFallbackCopy(QStringLiteral("Windows could not replace the original (error %1).")
                     .arg(static_cast<qulonglong>(err)));
#else
    Q_UNUSED(attempt)
    saveFallbackCopy(QStringLiteral("Replacing the original is supported only on Windows."));
#endif
}

void VideoExportController::saveFallbackCopy(const QString &reason)
{
    // Preserve successful work if replacement is blocked; never remove
    // an original or backup to make room for an output.
    const QString output = suggestedOutputUrl(m_pendingSource).toLocalFile();
    if (QFileInfo::exists(output) || !QFile::rename(m_temporaryOutput, output)) {
        m_busy = false;
        m_replacePending = false;
        m_error = reason + QStringLiteral(" Inspect original and any backup. Encoded video remains at: ") + m_temporaryOutput;
        m_status.clear();
        emit stateChanged();
        return;
    }
    markCompleted(output, false);
    m_status = QStringLiteral("Replacement not confirmed. Edited copy saved; inspect original and backup.");
    m_error = reason;
    emit stateChanged();
}

void VideoExportController::fail(const QString &message)
{
    if (!m_temporaryOutput.isEmpty())
        QFile::remove(m_temporaryOutput);
    m_busy = false;
    m_cancelRequested = false;
    m_error = message;
    m_status.clear();
    emit stateChanged();
}

void VideoExportController::cancel()
{
    if (!m_busy || m_cancelRequested)
        return;
    m_cancelRequested = true;
    if (m_replacePending) {
        QFile::remove(m_temporaryOutput);
        m_busy = false;
        m_replacePending = false;
        m_status = QStringLiteral("Replacement canceled. Original unchanged.");
        m_error.clear();
        emit stateChanged();
        return;
    }
    m_status = QStringLiteral("Canceling export...");
    emit stateChanged();
    m_process.kill();
}
