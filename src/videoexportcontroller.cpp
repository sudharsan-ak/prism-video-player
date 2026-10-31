#include "videoexportcontroller.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
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

VideoExportController::VideoExportController(QObject *parent) : QObject(parent)
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
                                      double endSeconds, const QUrl &destination)
{
    if (m_busy)
        return false;

    m_error.clear();
    m_lastOutput = {};
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
    if (!std::isfinite(startSeconds) || !std::isfinite(endSeconds) ||
        startSeconds < 0.0 || endSeconds - startSeconds < 0.1) {
        fail(QStringLiteral("Trim end must be at least 0.1 seconds after the start."));
        return false;
    }
    const QString inputCanonical = source.canonicalFilePath();
    if (inputCanonical.compare(output.absoluteFilePath(), Qt::CaseInsensitive) == 0 ||
        output.exists()) {
        fail(QStringLiteral("Choose a new filename. Prism never overwrites existing videos."));
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
    m_temporaryOutput = QDir(output.absolutePath()).filePath(
        QStringLiteral(".prism-export-%1.mp4").arg(QUuid::createUuid().toString(QUuid::WithoutBraces)));
    m_clipDuration = endSeconds - startSeconds;
    m_progress = 0.0;
    m_progressBuffer.clear();
    m_lastStderr.clear();
    m_cancelRequested = false;
    m_busy = true;
    m_status = QStringLiteral("Encoding trimmed clip...");
    emit progressChanged();
    emit stateChanged();

    // Always re-encode for accurate cuts at non-keyframes. First audio
    // track only, no subtitles in the Phase 1 trim-export implementation.
    // FFmpeg receives separate argv elements, never a shell command.
    const QStringList args = {
        QStringLiteral("-hide_banner"), QStringLiteral("-nostdin"),
        QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-stats_period"), QStringLiteral("0.25"),
        QStringLiteral("-progress"), QStringLiteral("pipe:1"),
        QStringLiteral("-n"), QStringLiteral("-ss"), QString::number(startSeconds, 'f', 3),
        QStringLiteral("-protocol_whitelist"), QStringLiteral("file,crypto,data"),
        QStringLiteral("-i"), source.absoluteFilePath(),
        QStringLiteral("-t"), QString::number(m_clipDuration, 'f', 3),
        QStringLiteral("-map"), QStringLiteral("0:V:0"),
        QStringLiteral("-map"), QStringLiteral("0:a:0?"),
        QStringLiteral("-c:v"), QStringLiteral("libx264"),
        QStringLiteral("-preset"), QStringLiteral("fast"),
        QStringLiteral("-crf"), QStringLiteral("18"),
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
    if (QFileInfo::exists(m_pendingOutput) || !QFile::rename(m_temporaryOutput, m_pendingOutput)) {
        fail(QStringLiteral("Could not save the edited video. Check the folder and output name."));
        return;
    }
    m_lastOutput = QUrl::fromLocalFile(m_pendingOutput);
    m_progress = 1.0;
    m_busy = false;
    m_status = QStringLiteral("Export complete.");
    m_error.clear();
    emit progressChanged();
    emit stateChanged();
    emit completed(m_lastOutput);
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
    m_status = QStringLiteral("Canceling export...");
    emit stateChanged();
    m_process.kill();
}
