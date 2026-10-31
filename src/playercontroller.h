#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QTimer>

class MpvObject;
class SettingsStore;

// Everything the QML top bar, context menu, and control bar call into.
// Mirrors the mpv command surface the Electron build proved out (see
// PHASE1_PLAN_QT.md section 3), re-platformed against libmpv directly
// instead of JSON-IPC. Also owns the local-only file validation (no
// URLs, no UNC paths) and the queue/recent/bookmark/resume state.
class PlayerController : public QObject {
    Q_OBJECT
    Q_PROPERTY(MpvObject *mpv READ mpv WRITE setMpv NOTIFY mpvChanged)
    Q_PROPERTY(QStringList playlist READ playlist NOTIFY playlistChanged)
    Q_PROPERTY(int currentIndex READ currentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(QVariantList bookmarks READ bookmarks NOTIFY bookmarksChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit PlayerController(SettingsStore *settings, QObject *parent = nullptr);

    MpvObject *mpv() const { return m_mpv; }
    void setMpv(MpvObject *mpv);

    QStringList playlist() const { return m_playlist; }
    int currentIndex() const { return m_currentIndex; }
    QVariantList bookmarks() const { return m_bookmarks; }
    QString lastError() const { return m_lastError; }

    // Local-only validation: rejects UNC paths, URL schemes, and
    // unsupported extensions. Same posture as the Electron build's
    // validLocalFile() (main.cjs:34-40).
    Q_INVOKABLE bool isValidLocalFile(const QString &path) const;

public slots:
    void openFiles(const QStringList &paths);
    void addToQueue(const QStringList &paths);
    void playRecent(const QString &path);
    void playAtIndex(int index);
    void next();
    void previous();
    void clearQueue();
    void removeFromQueue(int index);

    void togglePause();
    void setPaused(bool paused);
    void seek(double seconds);
    void skip(double deltaSeconds);
    void setVolume(int volume);
    void setSpeed(double speed);
    void frameStepForward();
    void frameStepBackward();

    void setSubtitleTrack(const QVariant &id);
    void setAudioTrack(const QVariant &id);
    void setSubtitleDelay(double seconds);
    void setAudioDelay(double seconds);
    void loadExternalSubtitle(const QString &path);

    void setAspectRatio(const QString &aspect);
    void setRotation(int quarterTurns);
    void setBrightness(int value);
    void setContrast(int value);
    void setSaturation(int value);
    void setGamma(int value);

    void setLoopA();
    void setLoopB();
    void clearLoop();

    void addBookmarkHere();
    void removeBookmarkAt(double time);
    void seekToBookmark(double time);

    QString takeScreenshot();

private slots:
    void onFileLoaded();
    void onEndOfFile(const QString &reason);
    void onEofReachedChanged();
    void onPositionChanged();
    void onPathChanged();
    void persistResumePosition();

signals:
    void mpvChanged();
    void playlistChanged();
    void currentIndexChanged();
    void bookmarksChanged();
    void lastErrorChanged();
    void notify(const QString &message, const QString &type);

private:
    void playIndex(int index);
    void setError(const QString &message);
    void refreshBookmarks();
    QStringList filterValid(const QStringList &paths) const;

    MpvObject *m_mpv = nullptr;
    SettingsStore *m_settings;

    QStringList m_playlist;
    int m_currentIndex = -1;
    QVariantList m_bookmarks;
    QString m_lastError;

    QTimer m_resumeSaveTimer;
    qint64 m_lastResumeWriteMs = 0;
};
