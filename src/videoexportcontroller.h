#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QUrl>
#include <QDateTime>

// Runs local, non-destructive FFmpeg trim exports. Export runs asynchronously;
// Prism's libmpv video playback and GUI thread remain independent of encoding.
class VideoExportController : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(QUrl lastOutput READ lastOutput NOTIFY stateChanged)
    Q_PROPERTY(bool lastWasReplacement READ lastWasReplacement NOTIFY stateChanged)
    Q_PROPERTY(QString backupPath READ backupPath NOTIFY stateChanged)

public:
    explicit VideoExportController(QObject *parent = nullptr);
    bool busy() const { return m_busy; }
    double progress() const { return m_progress; }
    QString status() const { return m_status; }
    QString error() const { return m_error; }
    QUrl lastOutput() const { return m_lastOutput; }
    bool lastWasReplacement() const { return m_lastWasReplacement; }
    QString backupPath() const { return m_backupPath; }

    Q_INVOKABLE QUrl suggestedOutputUrl(const QString &sourcePath) const;
    Q_INVOKABLE bool startTrim(const QString &sourcePath, double startSeconds,
                              double endSeconds, const QUrl &destination);
    Q_INVOKABLE bool startReplaceTrim(const QString &sourcePath, double startSeconds, double endSeconds);
    Q_INVOKABLE void completeReplacement();
    Q_INVOKABLE void cancel();

signals:
    void stateChanged();
    void progressChanged();
    void completed(const QUrl &outputUrl);
    void replacementPrepared();

private:
    QString ffmpegExecutable() const;
    void fail(const QString &message);
    void parseProgress(const QByteArray &chunk);
    void finished(int exitCode, QProcess::ExitStatus exitStatus);
    bool beginTrim(const QString &sourcePath, double startSeconds, double endSeconds,
                   const QUrl &destination, bool replaceOriginal);
    void finalizeReplacement(int attempt);
    void saveFallbackCopy(const QString &reason);
    void markCompleted(const QString &outputPath, bool replaced);

    QProcess m_process;
    bool m_busy = false;
    bool m_cancelRequested = false;
    double m_progress = 0.0;
    double m_clipDuration = 0.0;
    QString m_status;
    QString m_error;
    QString m_pendingOutput;
    QString m_pendingSource;
    QString m_backupPath;
    qint64 m_sourceSize = 0;
    QDateTime m_sourceModified;
    bool m_replaceOriginal = false;
    bool m_replacePending = false;
    bool m_lastWasReplacement = false;
    QString m_temporaryOutput;
    QByteArray m_progressBuffer;
    QString m_lastStderr;
    QUrl m_lastOutput;
};
