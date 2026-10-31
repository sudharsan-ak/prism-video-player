#include "themecontroller.h"
#include "settingsstore.h"

ThemeController::ThemeController(SettingsStore *settings, QObject *parent)
    : QObject(parent), m_settings(settings)
{
    buildThemeTable();
    m_activeThemeName = m_settings->themeName();
    if (!m_themes.contains(m_activeThemeName))
        m_activeThemeName = QStringLiteral("warmGlass");
}

void ThemeController::setActiveThemeName(const QString &name)
{
    if (name == m_activeThemeName || !m_themes.contains(name))
        return;
    m_activeThemeName = name;
    m_settings->setThemeName(name);
    emit activeThemeChanged();
}

QVariantMap ThemeController::tokens() const
{
    return m_themes.value(m_activeThemeName);
}

QVariantList ThemeController::availableThemes() const
{
    QVariantList result;
    for (const auto &pair : m_themeOrder) {
        QVariantMap entry;
        entry["id"] = pair.first;
        entry["displayName"] = pair.second;
        result.append(entry);
    }
    return result;
}

void ThemeController::buildThemeTable()
{
    // Warm Glass: locked default. Cream/tan gradient, clay/amber accent,
    // frosted glass panels. See PHASE1_PLAN_QT.md section 6.1.
    {
        QVariantMap t;
        t["backgroundGradient"] = QVariantList{"#F5F1E6", "#EDE6D6", "#E6DCC6"};
        t["textPrimary"] = "#2B2A26";
        t["textSecondary"] = "#6B6A5F";
        t["textMuted"] = "#8A8975";
        t["accentGradient"] = QVariantList{"#E2A86F", "#D97757"};
        t["accentSolid"] = "#D97757";
        t["accentTint"] = "#24D97757";
        t["panelGlass"] = "#8CFFFDF7";
        t["panelGlassStrong"] = "#E6FFFDF7";
        t["panelBorder"] = "#1A2B2A26";
        t["videoCardBackground"] = "#141210";
        t["videoCardShadow"] = "#2E5A4628";
        t["blurRadius"] = 20;
        m_themes["warmGlass"] = t;
        m_themeOrder.append(qMakePair(QString("warmGlass"), QString("Warm Glass")));
    }
    // Cool Glass: same structure, sky-blue/teal palette.
    {
        QVariantMap t;
        t["backgroundGradient"] = QVariantList{"#EAF1F5", "#DCE8EE", "#CFE0E8"};
        t["textPrimary"] = "#1E2B30";
        t["textSecondary"] = "#59707A";
        t["textMuted"] = "#6B848D";
        t["accentGradient"] = QVariantList{"#6FC3DB", "#2E8FB0"};
        t["accentSolid"] = "#2E8FB0";
        t["accentTint"] = "#242E8FB0";
        t["panelGlass"] = "#8CF8FCFD";
        t["panelGlassStrong"] = "#E6F8FCFD";
        t["panelBorder"] = "#1A1E2B30";
        t["videoCardBackground"] = "#0D1418";
        t["videoCardShadow"] = "#2E284655";
        t["blurRadius"] = 20;
        m_themes["coolGlass"] = t;
        m_themeOrder.append(qMakePair(QString("coolGlass"), QString("Cool Glass")));
    }
    // Midnight Glass: dark base, violet accent, real glass blur.
    {
        QVariantMap t;
        t["backgroundGradient"] = QVariantList{"#1C1D26", "#15161E", "#101118"};
        t["textPrimary"] = "#E8E7F0";
        t["textSecondary"] = "#9693AA";
        t["textMuted"] = "#8D89A3";
        t["accentGradient"] = QVariantList{"#A89BFF", "#6F5CE0"};
        t["accentSolid"] = "#6F5CE0";
        t["accentTint"] = "#2E6F5CE0";
        t["panelGlass"] = "#8C1C1D26";
        t["panelGlassStrong"] = "#E61C1D26";
        t["panelBorder"] = "#14FFFFFF";
        t["videoCardBackground"] = "#000000";
        t["videoCardShadow"] = "#66000000";
        t["blurRadius"] = 22;
        m_themes["midnightGlass"] = t;
        m_themeOrder.append(qMakePair(QString("midnightGlass"), QString("Midnight Glass")));
    }
    // OLED Neon: true black, zero blur, neon-green accent.
    {
        QVariantMap t;
        t["backgroundGradient"] = QVariantList{"#000000", "#000000", "#000000"};
        t["textPrimary"] = "#F2F2F2";
        t["textSecondary"] = "#8A8A8A";
        t["textMuted"] = "#6E6E6E";
        t["accentGradient"] = QVariantList{"#39FF88", "#39FF88"};
        t["accentSolid"] = "#39FF88";
        t["accentTint"] = "#1F39FF88";
        t["panelGlass"] = "#000000";
        t["panelGlassStrong"] = "#000000";
        t["panelBorder"] = "#1A1A1A";
        t["videoCardBackground"] = "#000000";
        t["videoCardShadow"] = "#00000000";
        t["blurRadius"] = 0;
        m_themes["oledNeon"] = t;
        m_themeOrder.append(qMakePair(QString("oledNeon"), QString("OLED Neon")));
    }
    // Soft Neumorphic: tactile raised/inset shadows, no transparency.
    {
        QVariantMap t;
        t["backgroundGradient"] = QVariantList{"#E8E6E1", "#E8E6E1", "#E8E6E1"};
        t["textPrimary"] = "#36352E";
        t["textSecondary"] = "#6E6C62";
        t["textMuted"] = "#8A8775";
        t["accentGradient"] = QVariantList{"#F2A65A", "#D97757"};
        t["accentSolid"] = "#D97757";
        t["accentTint"] = "#1FD97757";
        t["panelGlass"] = "#E8E6E1";
        t["panelGlassStrong"] = "#E8E6E1";
        t["panelBorder"] = "transparent";
        t["videoCardBackground"] = "#141210";
        t["videoCardShadow"] = "#2E000000";
        t["blurRadius"] = 0;
        t["neumorphic"] = true;
        m_themes["softNeumorphic"] = t;
        m_themeOrder.append(qMakePair(QString("softNeumorphic"), QString("Soft Neumorphic")));
    }
    // Terminal Flat: Solarized dark, monospace, flat borders.
    {
        QVariantMap t;
        t["backgroundGradient"] = QVariantList{"#002B36", "#002B36", "#002B36"};
        t["textPrimary"] = "#EEE8D5";
        t["textSecondary"] = "#93A1A1";
        t["textMuted"] = "#657B83";
        t["accentGradient"] = QVariantList{"#2AA198", "#2AA198"};
        t["accentSolid"] = "#2AA198";
        t["accentTint"] = "#242AA198";
        t["panelGlass"] = "#00212B";
        t["panelGlassStrong"] = "#00212B";
        t["panelBorder"] = "#073642";
        t["videoCardBackground"] = "#000000";
        t["videoCardShadow"] = "#00000000";
        t["blurRadius"] = 0;
        t["monospace"] = true;
        m_themes["terminalFlat"] = t;
        m_themeOrder.append(qMakePair(QString("terminalFlat"), QString("Terminal Flat")));
    }
}
