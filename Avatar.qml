import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One person, drawn one of two ways.
//
// The initials disc is always painted: it is the fallback, and it fills the
// frame while a remote image is still in flight. The photo is layered over it
// only when the widget is set to show avatars and the image actually arrives,
// so a Fizzy that keeps avatars behind auth, or a dropped connection, degrades
// to exactly what this plugin drew before.
//
// The seat stays a circle either way: most people on an account have no
// picture, so a shape that changed with the setting would leave a row mixing
// two silhouettes for no gain.
Item {
  id: root

  property var user: null
  property var panel: null
  property real size: Style.space(20)
  property real tintAlpha: 0.35
  property real initialsScale: 0.44
  property real borderWidth: 0
  property color borderColor: "transparent"

  // The picture to paint over the initials, or "" for the great majority of
  // people who never uploaded one. Panel.avatarUrlFor is what decides: Fizzy
  // answers with an SVG it draws itself otherwise, and Qt cannot render it.
  property string photoUrl: ""

  readonly property string personName: user && user.name ? String(user.name) : ""
  readonly property real cornerRadius: size / 2

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  Rectangle {
    anchors.fill: parent
    radius: root.cornerRadius
    color: Util.alpha(
      Model.avatarColor(root.personName, root.panel ? root.panel.lightTheme : false),
      root.tintAlpha)

    Text {
      anchors.centerIn: parent
      text: Model.initials(root.personName)
      color: root.panel ? root.panel.ink : Color.foreground
      font.family: root.panel ? root.panel.fontFamily : Style.font.family
      font.pixelSize: Math.round(root.size * root.initialsScale)
    }
  }

  Image {
    id: photo
    anchors.fill: parent
    source: root.photoUrl
    asynchronous: true
    cache: true
    fillMode: Image.PreserveAspectCrop
    // Fizzy serves SVG for people who never uploaded a picture, and sourceSize
    // is what tells the renderer how big to rasterize that; it also caps a
    // full-resolution photo at something a 16px seat can actually use.
    sourceSize.width: Math.ceil(root.size * 3)
    sourceSize.height: Math.ceil(root.size * 3)
    visible: false
  }

  // Qt's rounded-image recipe: a layered shape is the mask, the effect clips
  // the photo to it. The mask has to fill the same box as the effect, or it is
  // scaled to fit and the corners land in the wrong place.
  Rectangle {
    id: photoMask
    anchors.fill: parent
    radius: root.cornerRadius
    color: "black"
    visible: false
    layer.enabled: true
    layer.smooth: true
  }

  MultiEffect {
    anchors.fill: parent
    source: photo
    maskEnabled: true
    maskSource: photoMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 0.2
    visible: photo.status === Image.Ready
    opacity: photo.status === Image.Ready ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  }

  // The ring rides on top rather than on the disc below: a photo covers the
  // disc completely, and the ring is what keeps overlapping seats legible.
  Rectangle {
    anchors.fill: parent
    radius: root.cornerRadius
    color: "transparent"
    visible: root.borderWidth > 0
    border.width: root.borderWidth
    border.color: root.borderColor
  }
}
