#include "videoexportcontroller.h"
#include "settingsstore.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QVariantMap>
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

VideoExportController::~VideoExportController()
{
    // Only discard a partial file if FFmpeg is still encoding.
    // Preserve a completed temp file if Windows replacement/fallback
    // failed and its path was reported to the user for recovery.
    if (m_process.state() != QProcess::NotRunning) {
        m_process.disconnect(this);
        m_process.kill();
        m_process.waitForFinished(2000);
        if (!m_temporaryOutput.isEmpty())
            QFile::remove(m_temporaryOutput);
    }
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

QUrl VideoExportController::suggestedGifOutputUrl(const QString &sourcePath) const
{
    const QFileInfo info(sourcePath);
    const QString basename = info.completeBaseName().isEmpty()
        ? QStringLiteral("Prism-video") : info.completeBaseName();
    const QString folder = info.isFile() ? info.absolutePath()
        : QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    QString path = QDir(folder).filePath(basename + QStringLiteral("-trimmed.gif"));
    for (int n = 2; QFileInfo::exists(path); ++n)
        path = QDir(folder).filePath(basename + QStringLiteral("-trimmed-%1.gif").arg(n));
    return QUrl::fromLocalFile(path);
}

bool VideoExportController::startTrim(const QString &sourcePath, double startSeconds,
                                      double endSeconds, const QUrl &destination,
                                      double playbackSpeed, int audioVolumePercent,
                                      const QString &encodingPreset, int quarterTurns,
                                      double cropX, double cropY, double cropWidth, double cropHeight)
{
    return beginTrim(sourcePath, startSeconds, endSeconds, destination,
                     false, playbackSpeed, audioVolumePercent, false, encodingPreset, QString(),
                     quarterTurns, cropX, cropY, cropWidth, cropHeight);
}

bool VideoExportController::startReplaceTrim(const QString &sourcePath,
                                            double startSeconds, double endSeconds,
                                            double playbackSpeed, int audioVolumePercent,
                                            int quarterTurns, double cropX, double cropY,
                                            double cropWidth, double cropHeight)
{
    return beginTrim(sourcePath, startSeconds, endSeconds,
                     QUrl::fromLocalFile(sourcePath), true, playbackSpeed, audioVolumePercent,
                     false, QString(), QString(), quarterTurns, cropX, cropY, cropWidth, cropHeight);
}

bool VideoExportController::startGif(const QString &sourcePath, double startSeconds,
                                     double endSeconds, const QUrl &destination,
                                     double playbackSpeed, const QString &gifQuality,
                                     int quarterTurns, double cropX, double cropY,
                                     double cropWidth, double cropHeight)
{
    return beginTrim(sourcePath, startSeconds, endSeconds, destination,
                     false, playbackSpeed, 0, true, QString(), gifQuality,
                     quarterTurns, cropX, cropY, cropWidth, cropHeight);
}

bool VideoExportController::startSegments(const QString &sourcePath, const QVariantList &ranges,
                                          const QUrl &destination, bool animatedGif,
                                          double playbackSpeed, int audioVolumePercent,
                                          const QString &encodingPreset, const QString &gifQuality,
                                          int quarterTurns, double cropX, double cropY,
                                          double cropWidth, double cropHeight)
{
    if (ranges.isEmpty())
        return false;
    const QVariantMap first = ranges.first().toMap();
    const QVariantMap last = ranges.last().toMap();
    return beginTrim(sourcePath, first.value(QStringLiteral("start")).toDouble(),
                     last.value(QStringLiteral("end")).toDouble(), destination,
                     false, playbackSpeed, audioVolumePercent, animatedGif,
                     encodingPreset, gifQuality, quarterTurns,
                     cropX, cropY, cropWidth, cropHeight, ranges);
}

bool VideoExportController::beginTrim(const QString &sourcePath, double startSeconds,
                                      double endSeconds, const QUrl &destination,
                                      bool replaceOriginal, double playbackSpeed,
                                      int audioVolumePercent, bool animatedGif,
                                      const QString &encodingPreset,
                                      const QString &gifQuality, int quarterTurns,
                                      double cropX, double cropY,
                                      double cropWidth, double cropHeight,
                                      const QVariantList &ranges)
{
    if (m_busy)
        return false;
    if (audioVolumePercent < 0 || audioVolumePercent > 100) {
        fail(QStringLiteral("Audio volume must be between 0% and 100%."));
        return false;
    }
    // Crop coordinates are normalized to the ROTATED image so that the
    // on-screen crop rectangle maps to the same pixels in MP4 and GIF.
    constexpr double epsilon = 0.000001;
    if (quarterTurns < 0 || quarterTurns > 3 ||
        !std::isfinite(cropX) || !std::isfinite(cropY) ||
        !std::isfinite(cropWidth) || !std::isfinite(cropHeight) ||
        cropX < 0 || cropY < 0 || cropWidth < 0.05 || cropHeight < 0.05 ||
        cropX + cropWidth > 1.0 + epsilon || cropY + cropHeight > 1.0 + epsilon) {
        fail(QStringLiteral("Invalid crop or rotation settings."));
        return false;
    }

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
    const QString extension = animatedGif ? QStringLiteral("gif") : QStringLiteral("mp4");
    if (!isLocalAbsolutePath(sourcePath) || !source.isFile() || !source.isReadable() ||
        !destination.isLocalFile() || !isLocalAbsolutePath(outputPath) ||
        output.suffix().compare(extension, Qt::CaseInsensitive) != 0) {
        fail(QStringLiteral("Choose an existing local video and a new .%1 destination.").arg(extension));
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
    QList<QPair<double,double>> slices;
    double summedDuration = 0.0, previousEnd = -1;
    if (!ranges.isEmpty()) {
        if (replaceOriginal || ranges.size() > 100) {
            fail(QStringLiteral("Segment export cannot replace the original or exceed 100 pieces."));
            return false;
        }
        for (const QVariant &value : ranges) {
            const QVariantMap item = value.toMap();
            if (!item.contains(QStringLiteral("start")) || !item.contains(QStringLiteral("end"))) {
                fail(QStringLiteral("Invalid segment export range."));
                return false;
            }
            const double a = item.value(QStringLiteral("start")).toDouble();
            const double b = item.value(QStringLiteral("end")).toDouble();
            if (!std::isfinite(a) || !std::isfinite(b) || a < 0 ||
                b-a < 0.05 || a < previousEnd-0.0001) {
                fail(QStringLiteral("Segment export ranges must be ordered and nonoverlapping."));
                return false;
            }
            slices.append(qMakePair(a,b));
            summedDuration += b-a;
            previousEnd = b;
        }
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
    m_exportingGif = animatedGif;
    m_encodingPresetForJob = encodingPreset.isEmpty()
        ? (m_settings ? m_settings->encodingPreset() : QStringLiteral("veryfast"))
        : encodingPreset;
    m_gifQualityForJob = gifQuality.isEmpty()
        ? (m_settings ? m_settings->gifQualityPreset() : QStringLiteral("balanced"))
        : gifQuality;
    // Only allow known values into FFmpeg's argument list.
    if (m_encodingPresetForJob != QStringLiteral("ultrafast") &&
        m_encodingPresetForJob != QStringLiteral("veryfast") &&
        m_encodingPresetForJob != QStringLiteral("fast") &&
        m_encodingPresetForJob != QStringLiteral("medium") &&
        m_encodingPresetForJob != QStringLiteral("slow"))
        m_encodingPresetForJob = QStringLiteral("veryfast");
    if (m_gifQualityForJob != QStringLiteral("high") &&
        m_gifQualityForJob != QStringLiteral("balanced") &&
        m_gifQualityForJob != QStringLiteral("compact"))
        m_gifQualityForJob = QStringLiteral("balanced");
    m_playbackSpeed = playbackSpeed;
    m_keepBackupForJob = m_settings && m_settings->keepBackupOnReplace();
    m_temporaryOutput = QDir(output.absolutePath()).filePath(
        QStringLiteral(".prism-export-%1.%2")
            .arg(QUuid::createUuid().toString(QUuid::WithoutBraces), extension));
    const double sourceDuration = endSeconds - startSeconds;
    m_clipDuration = (slices.isEmpty() ? sourceDuration : summedDuration) / playbackSpeed;
    m_progress = 0.0;
    m_progressBuffer.clear();
    m_lastStderr.clear();
    m_cancelRequested = false;
    m_busy = true;
    m_status = animatedGif ? QStringLiteral("Creating animated GIF...")
        : replaceOriginal ? QStringLiteral("Encoding before safely replacing original...")
                          : QStringLiteral("Encoding trimmed copy...");
    emit progressChanged();
    emit stateChanged();

    // Apply the source trim before transforming timestamps; output time
    // is sourceDuration / playbackSpeed. Pass argv directly, no shell.
    const QString speed = QString::number(playbackSpeed, 'f', 3);
    QStringList editFilters { QStringLiteral("setpts=(PTS-STARTPTS)/") + speed };
    // Use the same filter order for MP4 and GIF: rotate first, crop
    // the rotated canvas second, then (for GIF only) scale/fps/palette.
    switch (quarterTurns) {
    case 1: editFilters << QStringLiteral("transpose=clock"); break;
    case 2: editFilters << QStringLiteral("hflip") << QStringLiteral("vflip"); break;
    case 3: editFilters << QStringLiteral("transpose=cclock"); break;
    default: break;
    }
    const bool fullFrame = std::abs(cropX) < epsilon && std::abs(cropY) < epsilon &&
                           std::abs(cropWidth - 1.0) < epsilon &&
                           std::abs(cropHeight - 1.0) < epsilon;
    if (!fullFrame) {
        // H.264 yuv420p and GIF size conversion behave best on even pixel
        // boundaries. At least two pixels remain in each direction.
        const QString crop = QStringLiteral(
            "crop=trunc(iw*%1/2)*2:trunc(ih*%2/2)*2:"
            "trunc(iw*%3/2)*2:trunc(ih*%4/2)*2")
            .arg(cropWidth, 0, 'f', 7)
            .arg(cropHeight, 0, 'f', 7)
            .arg(cropX, 0, 'f', 7)
            .arg(cropY, 0, 'f', 7);
        editFilters << crop;
    }
    const QString videoFilter = editFilters.join(QStringLiteral(","));
    const QString tempoFilter = playbackSpeed < 0.5
        ? QStringLiteral("atempo=0.5,atempo=") + QString::number(playbackSpeed / 0.5, 'f', 3)
        : QStringLiteral("atempo=") + speed;
    // Audio volume is a property of the exported file, not the current
    // Windows or Prism playback volume. At 100% leave source gain alone.
    const QString audioFilter = audioVolumePercent == 100 ? tempoFilter
        : tempoFilter + QStringLiteral(",volume=") +
          QString::number(audioVolumePercent / 100.0, 'f', 2);
    QStringList args = {
        QStringLiteral("-hide_banner"), QStringLiteral("-nostdin"),
        QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-stats_period"), QStringLiteral("0.25"),
        QStringLiteral("-progress"), QStringLiteral("pipe:1"),
        QStringLiteral("-n")
    };
    if (slices.isEmpty()) {
        args << QStringLiteral("-ss") << QString::number(startSeconds, 'f', 3)
             << QStringLiteral("-t") << QString::number(sourceDuration, 'f', 3);
    }
    args << QStringLiteral("-protocol_whitelist") << QStringLiteral("file,crypto,data")
         << QStringLiteral("-i") << source.absoluteFilePath();

    // Multi-range video uses trim/setpts per source range then concat.
    // Audio uses aselect/asetpts on the optional first audio stream.
    // One FFmpeg invocation encodes all retained segments without ever
    // rewriting, truncating or moving the source media.
    QString multiGraph;
    QString multiAudio;
    if (!slices.isEmpty()) {
        const int n = slices.size();
        QStringList parts;
        if (n > 1) {
            QString split = QStringLiteral("[0:v]split=%1").arg(n);
            for (int i=0;i<n;++i) split += QStringLiteral("[vs%1]").arg(i);
            parts << split;
        }
        QString inputs;
        QStringList audioClauses;
        for (int i=0;i<n;++i) {
            const double a=slices[i].first, b=slices[i].second;
            const QString ts = QStringLiteral("trim=start=%1:end=%2,setpts=PTS-STARTPTS")
                .arg(a,0,'f',6).arg(b,0,'f',6);
            parts << QStringLiteral("%1%2[v%3]")
                .arg(n>1 ? QStringLiteral("[vs%1]").arg(i) : QStringLiteral("[0:v]"))
                .arg(ts).arg(i);
            inputs += QStringLiteral("[v%1]").arg(i);
            audioClauses << QStringLiteral("between(t\\,%1\\,%2)")
                .arg(a,0,'f',6).arg(b,0,'f',6);
        }
        if (n > 1)
            parts << inputs + QStringLiteral("concat=n=%1:v=1:a=0[joined]").arg(n);
        else
            parts << QStringLiteral("[v0]null[joined]");
        parts << QStringLiteral("[joined]%1[vout]").arg(videoFilter);
        multiGraph = parts.join(QStringLiteral(";"));
        multiAudio = QStringLiteral("aselect='%1',asetpts=N/SR/TB,%2")
            .arg(audioClauses.join(QStringLiteral("+")),audioFilter);
    }
    if (animatedGif) {
        // Palette from the first two output seconds keeps GIF startup
        // fast. Balanced/Compact prioritize file size and fewer colors.
        const bool high = m_gifQualityForJob == QStringLiteral("high");
        const bool compact = m_gifQualityForJob == QStringLiteral("compact");
        const int width = high ? 640 : (compact ? 360 : 480);
        const int fps = high ? 12 : (compact ? 8 : 10);
        const int colors = high ? 256 : (compact ? 96 : 128);
        const QString paletteOptions = high ? QStringLiteral("stats_mode=full")
            : QStringLiteral("max_colors=%1:stats_mode=diff").arg(colors);
        const QString useOptions = high ? QStringLiteral("dither=sierra2_4a")
            : QStringLiteral("dither=bayer:bayer_scale=%1:diff_mode=rectangle")
                  .arg(compact ? 4 : 3);
        const QString gifFilter = QStringLiteral(
            "[0:v]%1,fps=%2,"
            "scale='min(%3,iw)':-1:flags=lanczos,split[frames][colors];"
            "[colors]trim=duration=2,setpts=PTS-STARTPTS,"
            "palettegen=%4[palette];"
            "[frames][palette]paletteuse=%5[gifout]")
                .arg(videoFilter).arg(fps).arg(width).arg(paletteOptions).arg(useOptions);
        const QString graph = slices.isEmpty() ? gifFilter :
            multiGraph + QStringLiteral(";") +
            QString(gifFilter).replace(QStringLiteral("[0:v]%1,").arg(videoFilter),
                                       QStringLiteral("[vout]"));
        args << QStringLiteral("-filter_complex") << graph
             << QStringLiteral("-map") << QStringLiteral("[gifout]")
             << QStringLiteral("-an")
             << QStringLiteral("-loop") << QStringLiteral("0")
             << QStringLiteral("-f") << QStringLiteral("gif");
    } else {
        if (slices.isEmpty()) {
            args << QStringLiteral("-map") << QStringLiteral("0:V:0");
        } else {
            args << QStringLiteral("-filter_complex") << multiGraph
                 << QStringLiteral("-map") << QStringLiteral("[vout]");
        }
        if (audioVolumePercent == 0) {
            // No audio stream is encoded, not just a stream of silence.
            args << QStringLiteral("-an");
        } else {
            args << QStringLiteral("-map") << QStringLiteral("0:a:0?")
                 << QStringLiteral("-af") << (slices.isEmpty() ? audioFilter : multiAudio)
                 << QStringLiteral("-c:a") << QStringLiteral("aac")
                 << QStringLiteral("-b:a") << QStringLiteral("192k");
        }
        if (slices.isEmpty()) args << QStringLiteral("-vf") << videoFilter;
        args << QStringLiteral("-c:v") << QStringLiteral("libx264")
             << QStringLiteral("-preset")
             << m_encodingPresetForJob
             << QStringLiteral("-crf") << QStringLiteral("18")
             << QStringLiteral("-pix_fmt") << QStringLiteral("yuv420p")
             << QStringLiteral("-movflags") << QStringLiteral("+faststart")
             << QStringLiteral("-f") << QStringLiteral("mp4");
    }
    args << m_temporaryOutput;
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
    // A successful fallback copy does not mean the requested replacement
    // succeeded. Preserve the failure reason BEFORE the completed signal
    // so QML shows a warning rather than the normal export-success toast.
    const bool replacementFellBackToCopy = m_replaceOriginal && !replaced;
    m_lastOutput = QUrl::fromLocalFile(outputPath);
    m_lastWasReplacement = replaced;
    m_progress = 1.0;
    m_busy = false;
    m_replacePending = false;
    m_status = replacementFellBackToCopy
        ? QStringLiteral("Replacement not confirmed. Edited copy saved; inspect original and backup.")
        : replaced
            ? (m_keepBackupForJob ? QStringLiteral("Original replaced. Backup saved.")
                                  : QStringLiteral("Original replaced. No backup requested."))
            : (m_exportingGif ? QStringLiteral("Animated GIF saved.")
                               : QStringLiteral("Edited MP4 saved."));
    if (!replacementFellBackToCopy)
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
    // Set the reason before markCompleted() emits stateChanged/completed.
    // The existing QML onCompleted handler can now distinguish this from
    // a normal MP4 copy and tell the user to inspect the original.
    m_error = reason;
    markCompleted(output, false);
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
