#include "playercontroller.h"
#include "mpvobject.h"
#include "settingsstore.h"

#include <QDebug>
#include <QFileInfo>
#include <QDir>
#include <QDateTime>
#include <QStandardPaths>
#include <QRegularExpression>
#include <QSet>

namespace {

const QSet<QString> &audioVideoExtensions()
{
    static const QSet<QString> exts = {
        "mp4", "mkv", "avi", "mov", "wmv", "webm", "flv", "m4v", "ts", "mts",
        "m2ts", "mpg", "mpeg", "3gp", "ogv", "vob", "divx", "mp3", "flac", "m4a",
        "aac", "ogg", "opus", "wav", "wma", "ape"
    };
    return exts;
}

const QSet<QString> &subtitleExtensions()
{
    static const QSet<QString> exts = {"srt", "ass", "ssa", "vtt", "sub", "idx", "smi"};
    return exts;
}

bool isLocalMediaFile(const QString &path, const QSet<QString> &allowedExtensions)
{
    if (path.isEmpty() || path.contains(QChar('\0')))
        return false;
    // Reject UNC paths and any URL-looking scheme; Prism is local-only
    // by design (see PHASE1_PLAN_QT.md section 5.3).
    if (path.startsWith("\\\\") || path.startsWith("//"))
        return false;
    if (QRegularExpression("^[a-zA-Z][a-zA-Z0-9+.-]*://").match(path).hasMatch())
        return false;
    QFileInfo info(path);
    if (!info.isAbsolute())
        return false;
    const QString ext = info.suffix().toLower();
    if (!allowedExtensions.contains(ext))
        return false;
    return info.isFile();
}

} // namespace

PlayerController::PlayerController(SettingsStore *settings, QObject *parent)
    : QObject(parent), m_settings(settings)
{
    m_resumeSaveTimer.setSingleShot(true);
    m_resumeSaveTimer.setInterval(1000);
    connect(&m_resumeSaveTimer, &QTimer::timeout, m_settings, &SettingsStore::save);
}

void PlayerController::setMpv(MpvObject *mpv)
{
    if (m_mpv == mpv)
        return;
    m_mpv = mpv;
    if (m_mpv) {
        connect(m_mpv, &MpvObject::fileLoaded, this, &PlayerController::onFileLoaded);
        connect(m_mpv, &MpvObject::endOfFile, this, &PlayerController::onEndOfFile);
        connect(m_mpv, &MpvObject::eofReachedChanged, this, &PlayerController::onEofReachedChanged);
        connect(m_mpv, &MpvObject::positionChanged, this, &PlayerController::onPositionChanged);
        connect(m_mpv, &MpvObject::mediaPathChanged, this, &PlayerController::onPathChanged);
        m_mpv->setProperty(QStringLiteral("volume"), m_settings->volume());
    }
    emit mpvChanged();
}

bool PlayerController::isValidLocalFile(const QString &path) const
{
    return isLocalMediaFile(path, audioVideoExtensions());
}

QStringList PlayerController::filterValid(const QStringList &paths) const
{
    QStringList valid;
    for (const QString &p : paths) {
        if (isValidLocalFile(p))
            valid.append(p);
    }
    return valid;
}

void PlayerController::openFiles(const QStringList &paths)
{
    const QStringList valid = filterValid(paths);
    if (valid.isEmpty()) {
        setError(QStringLiteral("No supported local media files found."));
        return;
    }
    m_playlist = valid;
    m_currentIndex = 0;
    emit playlistChanged();
    emit currentIndexChanged();
    playIndex(0);
}

void PlayerController::addToQueue(const QStringList &paths)
{
    const QStringList valid = filterValid(paths);
    if (valid.isEmpty())
        return;

    const bool wasEmpty = m_playlist.isEmpty();
    m_playlist.append(valid);
    emit playlistChanged();

    // "Add to queue" auto-plays only when the queue was empty, per the
    // library-panel behavior locked in PHASE1_PLAN_QT.md section 6.5.
    if (wasEmpty) {
        m_currentIndex = 0;
        emit currentIndexChanged();
        playIndex(0);
    }
}

void PlayerController::playRecent(const QString &path)
{
    if (!isValidLocalFile(path)) {
        setError(QStringLiteral("This file no longer exists or is not local."));
        return;
    }
    openFiles({path});
}

void PlayerController::playAtIndex(int index)
{
    if (index < 0 || index >= m_playlist.size())
        return;
    m_currentIndex = index;
    emit currentIndexChanged();
    playIndex(index);
}

void PlayerController::next()
{
    if (m_currentIndex + 1 < m_playlist.size())
        playAtIndex(m_currentIndex + 1);
}

void PlayerController::previous()
{
    if (m_currentIndex - 1 >= 0)
        playAtIndex(m_currentIndex - 1);
}

void PlayerController::clearQueue()
{
    m_playlist.clear();
    m_currentIndex = -1;
    emit playlistChanged();
    emit currentIndexChanged();
}

void PlayerController::removeFromQueue(int index)
{
    if (index < 0 || index >= m_playlist.size())
        return;

    m_playlist.removeAt(index);

    // Playback itself is untouched here - removing an item just takes
    // it off the list. If it was the one playing, currentIndex becomes
    // -1 (no longer "in" the queue) rather than skipping to another
    // file or stopping, since silently jumping elsewhere would be more
    // surprising than just delisting it.
    if (index == m_currentIndex)
        m_currentIndex = -1;
    else if (index < m_currentIndex)
        m_currentIndex -= 1;

    emit playlistChanged();
    emit currentIndexChanged();
}

void PlayerController::playIndex(int index)
{
    if (!m_mpv || index < 0 || index >= m_playlist.size())
        return;
    const QString path = m_playlist.at(index);
    m_settings->bumpRecent(path);
    refreshBookmarks();
    m_mpv->loadFile(path, false);
    // keep-open=yes leaves mpv paused on the last frame once a file ends;
    // without this, picking a new file (e.g. from Open Recent) after a
    // previous one finished loaded silently and stayed paused instead
    // of auto-playing.
    m_mpv->setProperty(QStringLiteral("pause"), false);
}

void PlayerController::onFileLoaded()
{
    if (!m_mpv || !m_settings->resumeEnabled())
        return;
    const double resume = m_settings->resumePositionFor(m_mpv->mediaPath());
    if (resume > 8.0)
        m_mpv->command(QVariantList{"seek", resume, "absolute", "exact"});
}

void PlayerController::onEndOfFile(const QString &reason)
{
    Q_UNUSED(reason);
    // Kept only for diagnostics/future use; onEofReachedChanged is the
    // actual advance trigger since the reason string here is not a
    // reliable "file genuinely finished" signal under keep-open=yes.
}

void PlayerController::onEofReachedChanged()
{
    if (!m_mpv || !m_mpv->eofReached())
        return;
    if (m_currentIndex + 1 < m_playlist.size())
        next();
}

void PlayerController::onPathChanged()
{
    refreshBookmarks();
}

void PlayerController::onPositionChanged()
{
    if (!m_mpv)
        return;
    const QString path = m_mpv->mediaPath();
    if (path.isEmpty())
        return;

    const double position = m_mpv->position();
    const double duration = m_mpv->duration();

    // Don't resume a file that's basically finished.
    if (duration > 0 && position >= duration - 8.0)
        m_settings->clearResumePositionFor(path);
    else
        m_settings->setResumePositionFor(path, position);

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - m_lastResumeWriteMs > 7000) {
        m_lastResumeWriteMs = now;
        if (!m_resumeSaveTimer.isActive())
            m_resumeSaveTimer.start();
    }
}

void PlayerController::persistResumePosition()
{
    m_settings->save();
}

void PlayerController::togglePause()
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("pause"), !m_mpv->paused());
}

void PlayerController::setPaused(bool paused)
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("pause"), paused);
}

void PlayerController::seek(double seconds)
{
    if (m_mpv)
        m_mpv->command(QVariantList{"seek", qBound(0.0, seconds, 864000.0), "absolute", "exact"});
}

void PlayerController::skip(double deltaSeconds)
{
    if (m_mpv)
        m_mpv->command(QVariantList{"seek", qBound(-3600.0, deltaSeconds, 3600.0), "relative"});
}

void PlayerController::setVolume(int volume)
{
    volume = qBound(0, volume, 100);
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("volume"), volume);
    m_settings->setVolume(volume);
}

void PlayerController::setSpeed(double speed)
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("speed"), qBound(0.25, speed, 4.0));
}

void PlayerController::frameStepForward()
{
    if (m_mpv)
        m_mpv->command(QVariantList{"frame-step"});
}

void PlayerController::frameStepBackward()
{
    if (m_mpv)
        m_mpv->command(QVariantList{"frame-back-step"});
}

void PlayerController::setSubtitleTrack(const QVariant &id)
{
    if (!m_mpv)
        return;
    m_mpv->setProperty(QStringLiteral("sid"), id.toString() == "no" ? QVariant("no") : id);
}

void PlayerController::setAudioTrack(const QVariant &id)
{
    if (!m_mpv)
        return;
    m_mpv->setProperty(QStringLiteral("aid"), id.toString() == "no" ? QVariant("no") : id);
}

void PlayerController::setSubtitleDelay(double seconds)
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("sub-delay"), qBound(-60.0, seconds, 60.0));
}

void PlayerController::setAudioDelay(double seconds)
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("audio-delay"), qBound(-60.0, seconds, 60.0));
}

void PlayerController::loadExternalSubtitle(const QString &path)
{
    if (!m_mpv)
        return;
    if (!isLocalMediaFile(path, subtitleExtensions())) {
        setError(QStringLiteral("Invalid subtitle file."));
        return;
    }
    m_mpv->command(QVariantList{"sub-add", path, "select"});
}

void PlayerController::setAspectRatio(const QString &aspect)
{
    static const QSet<QString> allowed = {"no", "16:9", "4:3", "1:1", "21:9"};
    if (!allowed.contains(aspect)) {
        setError(QStringLiteral("Invalid aspect ratio."));
        return;
    }
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("video-aspect-override"), aspect);
}

void PlayerController::setRotation(int quarterTurns)
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("video-rotate"), qBound(0, quarterTurns, 3) * 90);
}

void PlayerController::setBrightness(int value)
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("brightness"), qBound(-100, value, 100));
}

void PlayerController::setContrast(int value)
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("contrast"), qBound(-100, value, 100));
}

void PlayerController::setSaturation(int value)
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("saturation"), qBound(-100, value, 100));
}

void PlayerController::setGamma(int value)
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("gamma"), qBound(-100, value, 100));
}

void PlayerController::setLoopA()
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("ab-loop-a"), m_mpv->position());
}

void PlayerController::setLoopB()
{
    if (m_mpv)
        m_mpv->setProperty(QStringLiteral("ab-loop-b"), m_mpv->position());
}

void PlayerController::clearLoop()
{
    if (!m_mpv)
        return;
    m_mpv->setProperty(QStringLiteral("ab-loop-a"), QStringLiteral("no"));
    m_mpv->setProperty(QStringLiteral("ab-loop-b"), QStringLiteral("no"));
}

void PlayerController::refreshBookmarks()
{
    if (!m_mpv) {
        m_bookmarks = {};
    } else {
        m_bookmarks = m_settings->bookmarksFor(m_mpv->mediaPath());
    }
    emit bookmarksChanged();
}

void PlayerController::addBookmarkHere()
{
    if (!m_mpv || m_mpv->mediaPath().isEmpty())
        return;
    const double time = qRound(m_mpv->position() * 10) / 10.0;
    const int totalMinutes = static_cast<int>(time) / 60;
    const int seconds = static_cast<int>(time) % 60;
    const QString label = QStringLiteral("At %1:%2")
        .arg(totalMinutes)
        .arg(seconds, 2, 10, QChar('0'));
    m_settings->addBookmark(m_mpv->mediaPath(), time, label);
    refreshBookmarks();
}

void PlayerController::removeBookmarkAt(double time)
{
    if (!m_mpv)
        return;
    m_settings->removeBookmark(m_mpv->mediaPath(), time);
    refreshBookmarks();
}

void PlayerController::seekToBookmark(double time)
{
    seek(time);
}

QString PlayerController::takeScreenshot()
{
    if (!m_mpv || m_mpv->mediaPath().isEmpty()) {
        setError(QStringLiteral("Open a video before taking a screenshot."));
        return {};
    }
    const QString picturesDir = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    const QString folder = picturesDir + QStringLiteral("/Prism Captures");
    QDir().mkpath(folder);

    QFileInfo info(m_mpv->mediaPath());
    QString safeTitle = info.completeBaseName();
    safeTitle.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");
    safeTitle.truncate(60);

    const QString filename = QStringLiteral("%1-%2.png")
        .arg(safeTitle)
        .arg(QDateTime::currentMSecsSinceEpoch());
    const QString fullPath = folder + "/" + filename;

    const QString error = m_mpv->takeScreenshot(fullPath);
    if (!error.isEmpty()) {
        setError(QStringLiteral("Screenshot failed: %1").arg(error));
        return {};
    }
    emit notify(QStringLiteral("Saved screenshot to Pictures\\Prism Captures\\%1").arg(filename),
                QStringLiteral("success"));
    return filename;
}

void PlayerController::setError(const QString &message)
{
    m_lastError = message;
    emit lastErrorChanged();
    emit notify(message, QStringLiteral("error"));
}
