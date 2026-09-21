import QtQuick
import "../theme"

Text {
    id: icon

    // A glyph from the custom IconFont (assets/iconfont.ttf), e.g. "\ue024".
    // The font is self-assembled from SVGs; see Theme.qml for the loaded file.
    property string glyph

    // Deprecated no-op kept for config/API compatibility (IconFont is single-style)
    property string style: Theme.iconStyle
    // Deprecated no-op kept for API compatibility
    property bool brands: false

    text: glyph
    color: Theme.fgColor
    font.family: Theme.iconFont
    font.pixelSize: Theme.iconSize
}
