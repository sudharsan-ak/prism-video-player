#pragma once

#include <QObject>
#include <QDateTime>
#include <QProcess>
#include <QStringList>
#include <QTemporaryDir>
#include <QList>

// Extract real video frames without disturbing mpv playback. Two
// concurrent FFmpeg jobs keep the UI responsive. Last source is cached
// in the private temporary directory until Prism exits.
class VideoThumbnailController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList frames READ frames NOTIFY framesChanged)
    Q_PROPERTY(bool generating READ generating NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
public:
    explicit VideoThumbnailController(QObject *parent = nullptr);
    QStringList frames() const { return m_frames; }
    bool generating() const { return m_generating; }
    QString error() const { return m_error; }

    Q_INVOKABLE void generate(const QString &source, double duration);
    Q_INVOKABLE void stop();
signals:
    void framesChanged();
    void stateChanged();
private:
    QString ffmpegExecutable() const;
    void launchNext();

    QTemporaryDir m_cache;
    QList<QProcess *> m_processes;
    QStringList m_frames;
    QStringList m_cachedFrames;
    QString m_cachedSource;
    qint64 m_cachedSize = -1;
    QDateTime m_cachedModified;
    QString m_source;
    QString m_program;
    QString m_error;
    double m_duration = 0.0;
    int m_index = 0;
    quint64 m_generation = 0;
    bool m_generating = false;
};
