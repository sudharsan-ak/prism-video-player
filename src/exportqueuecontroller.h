#pragma once

#include <QObject>
#include <QDateTime>
#include <QList>
#include <QString>
#include <QUrl>
#include <QVariantList>

class SettingsStore;
class VideoExportController;

// Session-only export queue: a single FFmpeg worker runs one job at a
// time. Every queued job snapshots its source, range, options and output.
class ExportQueueController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList jobs READ jobs NOTIFY jobsChanged)
    Q_PROPERTY(int waitingCount READ waitingCount NOTIFY jobsChanged)
    Q_PROPERTY(bool hasOutstanding READ hasOutstanding NOTIFY jobsChanged)
    Q_PROPERTY(bool canQueue READ canQueue NOTIFY jobsChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY jobsChanged)

public:
    explicit ExportQueueController(VideoExportController *worker,
                                   SettingsStore *settings, QObject *parent = nullptr);
    QVariantList jobs() const;
    int waitingCount() const;
    bool hasOutstanding() const;
    bool canQueue() const;
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE QUrl suggestedOutputUrl(const QString &source, bool gif) const;
    Q_INVOKABLE bool queueMp4(const QString &source, double start, double end,
                             const QUrl &destination, double speed, bool muteAudio);
    Q_INVOKABLE bool queueGif(const QString &source, double start, double end,
                             const QUrl &destination, double speed);
    Q_INVOKABLE void cancelJob(int id);
    Q_INVOKABLE void clearFinished();

signals:
    void jobsChanged();

private:
    struct Job {
        int id = 0;
        QString source;
        QString output;
        QString format;
        QString state = QStringLiteral("Queued");
        QString error;
        QString mp4Preset;
        QString gifPreset;
        double start = 0.0;
        double end = 0.0;
        double speed = 1.0;
        double progress = 0.0;
        qint64 sourceSize = 0;
        QDateTime sourceModified;
        bool mute = false;
        bool cancelRequested = false;
    };

    bool enqueue(const QString &source, double start, double end,
                 const QUrl &destination, double speed, bool mute, bool gif);
    bool isReserved(const QString &output) const;
    Job *findJob(int id);
    void scheduleNext();
    void startNext();
    void finishActive(bool success, const QString &error = QString());

    VideoExportController *m_worker = nullptr;
    SettingsStore *m_settings = nullptr;
    QList<Job> m_jobs;
    int m_nextId = 1;
    int m_activeId = 0;
    QString m_lastError;
};
