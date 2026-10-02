import QtQuick
import "../theme"

Text {
    id: icon

    // A glyph from the custom icon font `aries-shell` (assets/iconfont.ttf), e.g. "\ue024".
    // The font is self-assembled from SVGs; see Theme.qml for the loaded file.
    property string glyph

    text: glyph
    color: Theme.fgColor
    font.family: Theme.iconFont
    font.pixelSize: Theme.iconSize
}
