#include "exportqueuecontroller.h"
#include "videoexportcontroller.h"
#include "settingsstore.h"

#include <QDir>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QVariantMap>
#include <QTimer>
#include <QtGlobal>
#include <cmath>

namespace {
bool safeLocalPath(const QString &path)
{
    return !path.isEmpty() && !path.contains(QChar('\0')) &&
        !path.startsWith(QStringLiteral("\\\\")) && !path.startsWith(QStringLiteral("//")) &&
        !QRegularExpression(QStringLiteral("^[a-zA-Z][a-zA-Z0-9+.-]*://")).match(path).hasMatch() &&
        QFileInfo(path).isAbsolute();
}
bool samePath(const QString &a, const QString &b)
{
#ifdef Q_OS_WIN
    return a.compare(b, Qt::CaseInsensitive) == 0;
#else
    return a == b;
#endif
}
}

ExportQueueController::ExportQueueController(VideoExportController *worker,
                                             SettingsStore *settings, QObject *parent)
    : QObject(parent), m_worker(worker), m_settings(settings)
{
    // The worker is owned by main.cpp, and outlives this queue manager.
    connect(worker, &VideoExportController::progressChanged, this, [this] {
        if (Job *job = findJob(m_activeId)) {
            job->progress = m_worker->progress();
            emit jobsChanged();
        }
    });
    connect(worker, &VideoExportController::completed, this, [this](const QUrl &) {
        if (m_activeId)
            finishActive(true);
    });
    connect(worker, &VideoExportController::stateChanged, this, [this] {
        if (Job *job = findJob(m_activeId)) {
            if (m_worker->busy()) {
                job->progress = m_worker->progress();
                emit jobsChanged();
            } else {
                // completed() follows stateChanged() on successful export.
                // Defer failure detection so the success signal wins.
                QTimer::singleShot(0, this, [this] {
                    if (m_activeId && !m_worker->busy())
                        finishActive(false, m_worker->error().isEmpty()
                            ? m_worker->status() : m_worker->error());
                });
            }
        } else {
            emit jobsChanged(); // replacement/exclusive state changed
        }
    });
}

QVariantList ExportQueueController::jobs() const
{
    QVariantList result;
    for (const Job &job : m_jobs) {
        QVariantMap item;
        item.insert(QStringLiteral("id"), job.id);
        item.insert(QStringLiteral("name"), QFileInfo(job.output).fileName());
        item.insert(QStringLiteral("source"), QFileInfo(job.source).fileName());
        item.insert(QStringLiteral("output"), job.output);
        item.insert(QStringLiteral("format"), job.format);
        item.insert(QStringLiteral("status"), job.state);
        item.insert(QStringLiteral("error"), job.error);
        item.insert(QStringLiteral("progress"), job.progress);
        item.insert(QStringLiteral("start"), job.start);
        item.insert(QStringLiteral("end"), job.end);
        item.insert(QStringLiteral("speed"), job.speed);
        item.insert(QStringLiteral("mute"), job.audioVolumePercent == 0);
        item.insert(QStringLiteral("audioVolume"), job.audioVolumePercent);
        item.insert(QStringLiteral("rotation"), job.quarterTurns * 90);
        item.insert(QStringLiteral("cropWidth"), job.cropWidth);
        item.insert(QStringLiteral("cropHeight"), job.cropHeight);
        item.insert(QStringLiteral("preset"), job.format == QStringLiteral("GIF")
            ? job.gifPreset : job.mp4Preset);
        result.append(item);
    }
    return result;
}

int ExportQueueController::waitingCount() const
{
    int count = 0;
    for (const Job &job : m_jobs)
        if (job.state == QStringLiteral("Queued"))
            ++count;
    return count;
}

bool ExportQueueController::hasOutstanding() const
{
    if (m_activeId)
        return true;
    return waitingCount() > 0;
}

bool ExportQueueController::canQueue() const
{
    // Export copy/GIF can be queued while another queued copy runs,
    // but not when the worker is replacing the original file.
    return m_activeId != 0 || !m_worker->busy();
}

bool ExportQueueController::isReserved(const QString &output) const
{
    for (const Job &job : m_jobs) {
        if ((job.state == QStringLiteral("Queued") || job.state == QStringLiteral("Running")) &&
            samePath(job.output, output))
            return true;
    }
    return false;
}

QUrl ExportQueueController::suggestedOutputUrl(const QString &source, bool gif) const
{
    const QFileInfo info(source);
    const QString stem = info.completeBaseName().isEmpty()
        ? QStringLiteral("Prism-video") : info.completeBaseName();
    const QString folder = info.isFile() ? info.absolutePath() :
        QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    const QString extension = gif ? QStringLiteral("gif") : QStringLiteral("mp4");
    const QString base = stem + QStringLiteral("-trimmed");
    for (int suffix = 1; suffix < 10000; ++suffix) {
        const QString name = base + (suffix == 1 ? QString()
            : QStringLiteral("-%1").arg(suffix)) + QStringLiteral(".") + extension;
        const QString candidate = QDir(folder).filePath(name);
        if (!QFileInfo::exists(candidate) && !isReserved(QFileInfo(candidate).absoluteFilePath()))
            return QUrl::fromLocalFile(candidate);
    }
    return {};
}

ExportQueueController::Job *ExportQueueController::findJob(int id)
{
    for (Job &job : m_jobs)
        if (job.id == id)
            return &job;
    return nullptr;
}

bool ExportQueueController::queueMp4(const QString &source, double start, double end,
                                     const QUrl &destination, double speed, int audioVolumePercent,
                                     int quarterTurns, double cropX, double cropY,
                                     double cropWidth, double cropHeight)
{
    return enqueue(source, start, end, destination, speed, audioVolumePercent, false,
                   quarterTurns, cropX, cropY, cropWidth, cropHeight);
}

bool ExportQueueController::queueGif(const QString &source, double start, double end,
                                     const QUrl &destination, double speed, int quarterTurns,
                                     double cropX, double cropY, double cropWidth,
                                     double cropHeight)
{
    return enqueue(source, start, end, destination, speed, 0, true,
                   quarterTurns, cropX, cropY, cropWidth, cropHeight);
}

bool ExportQueueController::enqueue(const QString &source, double start, double end,
                                    const QUrl &destination, double speed, int audioVolumePercent, bool gif,
                                    int quarterTurns, double cropX, double cropY,
                                    double cropWidth, double cropHeight)
{
    m_lastError.clear();
    auto reject = [this](const QString &error) {
        m_lastError = error;
        emit jobsChanged();
        return false;
    };
    if (!canQueue())
        return reject(QStringLiteral("Finish replacing the original video before adding exports."));
    if (!destination.isLocalFile() || !safeLocalPath(source) ||
        !safeLocalPath(destination.toLocalFile()))
        return reject(QStringLiteral("Only local video and output paths are supported."));
    const QFileInfo input(source);
    const QFileInfo output(QDir::cleanPath(destination.toLocalFile()));
    if (!input.isFile() || !input.isReadable())
        return reject(QStringLiteral("The source video cannot be read."));
    if (!QFileInfo(output.absolutePath()).isDir() || !QFileInfo(output.absolutePath()).isWritable())
        return reject(QStringLiteral("The output folder is not writable."));
    if (!std::isfinite(start) || !std::isfinite(end) || start < 0 ||
        end - start < 0.1 || !std::isfinite(speed) || speed < 0.25 || speed > 2.0 ||
        audioVolumePercent < 0 || audioVolumePercent > 100)
        return reject(QStringLiteral("Choose a valid trim range and a speed from 0.25x to 2x."));
    const bool validCrop = quarterTurns >= 0 && quarterTurns <= 3 &&
        std::isfinite(cropX) && std::isfinite(cropY) &&
        std::isfinite(cropWidth) && std::isfinite(cropHeight) &&
        cropX >= 0 && cropY >= 0 && cropWidth >= 0.05 && cropHeight >= 0.05 &&
        cropX + cropWidth <= 1.000001 && cropY + cropHeight <= 1.000001;
    if (!validCrop)
        return reject(QStringLiteral("Choose a valid crop and rotation."));
    if (output.suffix().compare(gif ? QStringLiteral("gif") :
                                QStringLiteral("mp4"), Qt::CaseInsensitive) != 0)
        return reject(QStringLiteral("Choose a matching MP4 or GIF filename."));
    if (samePath(input.canonicalFilePath(), output.absoluteFilePath()) ||
        output.exists() || isReserved(output.absoluteFilePath()))
        return reject(QStringLiteral("The output name already exists or is queued. Choose another name."));

    Job job;
    job.id = m_nextId++;
    job.source = input.absoluteFilePath();
    job.output = output.absoluteFilePath();
    job.format = gif ? QStringLiteral("GIF") : QStringLiteral("MP4");
    job.start = start;
    job.end = end;
    job.speed = speed;
    job.audioVolumePercent = audioVolumePercent;
    job.quarterTurns = quarterTurns;
    job.cropX = cropX;
    job.cropY = cropY;
    job.cropWidth = cropWidth;
    job.cropHeight = cropHeight;
    job.sourceSize = input.size();
    job.sourceModified = input.lastModified();
    job.mp4Preset = m_settings->encodingPreset();
    job.gifPreset = m_settings->gifQualityPreset();
    m_jobs.append(job);
    emit jobsChanged();
    scheduleNext();
    return true;
}

void ExportQueueController::scheduleNext()
{
    // Never nest a new worker start inside FFmpeg's finished handler.
    QTimer::singleShot(0, this, [this] { startNext(); });
}

void ExportQueueController::startNext()
{
    if (m_activeId || m_worker->busy())
        return;
    for (Job &job : m_jobs) {
        if (job.state != QStringLiteral("Queued"))
            continue;
        const QFileInfo current(job.source);
        if (!current.isFile() || current.size() != job.sourceSize ||
            current.lastModified() != job.sourceModified) {
            job.state = QStringLiteral("Failed");
            job.error = QStringLiteral("Source changed or disappeared before export.");
            emit jobsChanged();
            continue;
        }
        if (QFileInfo::exists(job.output)) {
            job.state = QStringLiteral("Failed");
            job.error = QStringLiteral("Output now exists; cannot overwrite it.");
            emit jobsChanged();
            continue;
        }
        job.state = QStringLiteral("Running");
        m_activeId = job.id;
        emit jobsChanged();

        const bool started = job.format == QStringLiteral("GIF")
            ? m_worker->startGif(job.source, job.start, job.end,
                  QUrl::fromLocalFile(job.output), job.speed, job.gifPreset,
                  job.quarterTurns, job.cropX, job.cropY, job.cropWidth, job.cropHeight)
            : m_worker->startTrim(job.source, job.start, job.end,
                  QUrl::fromLocalFile(job.output), job.speed, job.audioVolumePercent, job.mp4Preset,
                  job.quarterTurns, job.cropX, job.cropY, job.cropWidth, job.cropHeight);
        if (!started || !m_worker->busy())
            finishActive(false, m_worker->error());
        return;
    }
    emit jobsChanged();
}

void ExportQueueController::finishActive(bool success, const QString &error)
{
    const int finishedId = m_activeId;
    if (!finishedId)
        return;
    m_activeId = 0;
    if (Job *job = findJob(finishedId)) {
        if (job->cancelRequested) {
            job->state = QStringLiteral("Canceled");
        } else if (success) {
            job->state = QStringLiteral("Completed");
            job->progress = 1.0;
        } else {
            job->state = QStringLiteral("Failed");
            job->error = error.isEmpty() ? QStringLiteral("Export did not finish.") : error;
        }
    }
    emit jobsChanged();
    scheduleNext();
}

void ExportQueueController::cancelJob(int id)
{
    Job *job = findJob(id);
    if (!job)
        return;
    if (job->state == QStringLiteral("Queued")) {
        job->state = QStringLiteral("Canceled");
        emit jobsChanged();
    } else if (job->state == QStringLiteral("Running") && id == m_activeId) {
        job->cancelRequested = true;
        m_worker->cancel();
        emit jobsChanged();
    }
}

void ExportQueueController::clearFinished()
{
    m_jobs.removeIf([](const Job &job) {
        return job.state == QStringLiteral("Completed") ||
            job.state == QStringLiteral("Canceled") ||
            job.state == QStringLiteral("Failed");
    });
    emit jobsChanged();
}
