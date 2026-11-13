// The names Flash Player and Scaleform GFx define for AS2 code: the global classes and
// functions, the members of a movie clip, text field, and button, and the methods of the
// native classes. A miss on one of these is a runtime gap. A miss on any other name is a
// value the movie never set, which Flash also answers with `undefined`. Sources: Adobe
// "ActionScript 2.0 Language Reference" and Scaleform "GFx AS2 Extensions Reference".
// See docs/engine/as2-runtime.md#the-tally.

nonisolated enum AS2FlashNames {
    static func isDefined(_ name: String) -> Bool {
        globals.contains(name) || displayMembers.contains(name) || nativeMethods.contains(name)
    }

    /// `_global` names and the classes of the `flash.*` packages.
    static let globals: Set = [
        "Accessibility", "Array", "AsBroadcaster", "ASSetPropFlags", "BitmapData", "Boolean",
        "Button", "Camera", "Color", "ColorTransform", "ContextMenu", "ContextMenuItem", "Date",
        "Error", "ExternalInterface", "Function", "Infinity", "Key", "LoadVars", "LocalConnection",
        "Math", "Matrix", "Microphone", "Mouse", "MovieClip", "MovieClipLoader", "NaN",
        "NetConnection", "NetStream", "Number", "Object", "Point", "PrintJob", "Rectangle",
        "Selection", "SharedObject", "Sound", "Stage", "String", "System", "TextField",
        "TextFormat", "TextRenderer", "TextSnapshot", "Transform", "Video", "XML", "XMLNode",
        "XMLSocket", "BevelFilter", "BitmapFilter", "BlurFilter", "ColorMatrixFilter",
        "ConvolutionFilter", "DisplacementMapFilter", "DropShadowFilter", "GlowFilter",
        "GradientBevelFilter", "GradientGlowFilter", "FileReference", "FileReferenceList",
        "clearInterval", "clearTimeout", "escape", "getTimer", "getURL", "getVersion",
        "isFinite", "isNaN", "parseFloat", "parseInt", "setInterval", "setTimeout", "trace",
        "unescape", "updateAfterEvent", "flash", "geom", "filters", "display", "external",
        "net", "text", "gfxExtensions", "gfxVersion"
    ]

    /// Members of `MovieClip`, `TextField`, and `Button`, with the GFx extensions.
    static let displayMembers: Set = [
        "_alpha", "_currentframe", "_droptarget", "_focusrect", "_framesloaded", "_height",
        "_highquality", "_lockroot", "_name", "_parent", "_quality", "_rotation",
        "_soundbuftime", "_target", "_totalframes", "_url", "_visible", "_width", "_x",
        "_xmouse", "_xscale", "_y", "_ymouse", "_yscale", "blendMode", "cacheAsBitmap",
        "enabled", "filters", "focusEnabled", "forceSmoothing", "hitArea", "menu",
        "opaqueBackground", "scale9Grid", "scrollRect", "tabChildren", "tabEnabled", "tabIndex",
        "trackAsMenu", "transform", "useHandCursor", "attachAudio", "attachBitmap",
        "attachMovie", "beginBitmapFill", "beginFill", "beginGradientFill", "clear",
        "createEmptyMovieClip", "createTextField", "curveTo", "duplicateMovieClip", "endFill",
        "getBounds", "getBytesLoaded", "getBytesTotal", "getDepth", "getInstanceAtDepth",
        "getNextHighestDepth", "getRect", "getSWFVersion", "getTextSnapshot", "globalToLocal",
        "gotoAndPlay", "gotoAndStop", "hitTest", "lineGradientStyle", "lineStyle", "lineTo",
        "loadMovie", "loadVariables", "localToGlobal", "moveTo", "nextFrame", "play",
        "prevFrame", "removeMovieClip", "setMask", "startDrag", "stop", "stopDrag",
        "swapDepths", "unloadMovie", "antiAliasType", "autoSize", "background",
        "backgroundColor", "border", "borderColor", "bottomScroll", "condenseWhite",
        "embedFonts", "gridFitType", "hscroll", "html", "htmlText", "length", "maxChars",
        "maxhscroll", "maxscroll", "mouseWheelEnabled", "multiline", "password", "restrict",
        "scroll", "selectable", "sharpness", "styleSheet", "textColor", "textHeight",
        "textWidth", "thickness", "type", "variable", "wordWrap", "getFontList",
        "getNewTextFormat", "getTextFormat", "removeTextField", "replaceSel", "replaceText",
        "setNewTextFormat", "setTextFormat", "_z", "_xrotation", "_yrotation", "_zscale",
        "_perspfov", "_matrix3d", "topmostLevel", "noAdvance", "hitTestDisable",
        "focusGroupMask", "autoFit", "caretIndex", "fontScaleFactor", "noTranslate",
        "numLines", "textAutoSize", "verticalAlign", "verticalAutoSize", "appendText",
        "appendHtml", "getCharBoundaries", "getCharIndexAtPoint", "getExactCharBoundaries",
        "getFirstCharInParagraph", "getLineIndexAtPoint", "getLineLength", "getLineMetrics",
        "getLineOffset", "getLineText", "selectionBeginIndex", "selectionEndIndex"
    ]

    /// Methods of the native classes and of `Object.prototype`.
    static let nativeMethods: Set = [
        "addProperty", "hasOwnProperty", "isPropertyEnumerable", "isPrototypeOf",
        "registerClass", "toString", "unwatch", "valueOf", "watch", "apply", "call",
        "concat", "join", "pop", "push", "reverse", "shift", "slice", "sort", "sortOn",
        "splice", "unshift", "charAt", "charCodeAt", "fromCharCode", "indexOf", "lastIndexOf",
        "split", "substr", "substring", "toLowerCase", "toUpperCase", "abs", "acos", "asin",
        "atan", "atan2", "ceil", "cos", "exp", "floor", "log", "max", "min", "pow", "random",
        "round", "sin", "sqrt", "tan", "addListener", "removeListener", "broadcastMessage",
        "initialize", "getAscii", "getCode", "isDown", "isToggled", "hide", "show",
        "getBeginIndex", "getCaretIndex", "getEndIndex", "getFocus", "setFocus",
        "setSelection", "getRGB", "getTransform", "setRGB", "setTransform", "loadClip",
        "unloadClip", "getProgress", "getTextExtent", "addCallback", "clone", "contains",
        "containsPoint", "containsRectangle", "equals", "inflate", "inflatePoint",
        "intersection", "intersects", "isEmpty", "offset", "offsetPoint", "setEmpty", "union",
        "add", "subtract", "normalize", "distance", "interpolate", "polar", "getDate",
        "getDay", "getFullYear", "getHours", "getMilliseconds", "getMinutes", "getMonth",
        "getSeconds", "getTime", "getTimezoneOffset", "getYear", "setDate", "setFullYear",
        "setHours", "setMilliseconds", "setMinutes", "setMonth", "setSeconds", "setTime",
        "setYear", "attachSound", "getPan", "getVolume", "loadSound", "setPan", "setVolume",
        "start"
    ]
}
