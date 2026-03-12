import gtk2
nim_init()
type
    WindowToolkitKind* {.pure.} = enum
        Windows = 0
        Macosx
        Gtk
        Qt
    
    DialogButtonInfo* = tuple[title: string, responseType: int]

    GSListNode = object
        data: pointer
        next: pointer

const
    dialogFileOpenDefaultButtons*: seq[DialogButtonInfo] = @[
      (title: "Cancel", responseType: RESPONSE_CANCEL.int),
      (title: "Open", responseType: RESPONSE_ACCEPT.int)
    ]
    dialogFileSaveDefaultButtons*: seq[DialogButtonInfo] = @[
      (title: "Cancel", responseType: RESPONSE_CANCEL.int),
      (title: "Save", responseType: RESPONSE_ACCEPT.int)
    ]
    dialogFolderCreateDefaultButtons*: seq[DialogButtonInfo] = @[
      (title: "Cancel", responseType: RESPONSE_CANCEL.int),
      (title: "Create", responseType: RESPONSE_ACCEPT.int)
    ]
    dialogFolderSelectDefaultButtons*: seq[DialogButtonInfo] = @[
      (title: "Cancel", responseType: RESPONSE_CANCEL.int),
      (title: "Open", responseType: RESPONSE_ACCEPT.int)
    ]

{.passL: "-lgtk-x11-2.0".}
proc gtk_file_chooser_set_current_name(chooser: PFileChooser, name: cstring) {.importc.}
proc gtk_file_chooser_set_current_folder(chooser: PFileChooser, filename: cstring): cint {.importc.}
proc gtk_file_filter_new(): pointer {.importc.}
proc gtk_file_filter_set_name(filter: pointer, name: cstring) {.importc.}
proc gtk_file_filter_add_pattern(filter: pointer, pattern: cstring) {.importc.}
proc gtk_file_chooser_add_filter(chooser: PFileChooser, filter: pointer) {.importc.}
proc gtk_file_chooser_set_select_multiple(chooser: PFileChooser, selectMultiple: cint) {.importc.}
proc gtk_file_chooser_get_filenames(chooser: PFileChooser): pointer {.importc.}

proc addFilters(fileChooser: PFileChooser, filters: openArray[(string, string)]) =
    for (name, pattern) in filters:
        let f = gtk_file_filter_new()
        gtk_file_filter_set_name(f, name.cstring)
        gtk_file_filter_add_pattern(f, pattern.cstring)
        gtk_file_chooser_add_filter(fileChooser, f)

proc callDialogFile(action: TFileChooserAction, title: string, buttons: seq[DialogButtonInfo] = @[], defaultName: string = "", defaultDir: string = "", filters: openArray[(string, string)] = []): string =
    var dialog = file_chooser_dialog_new(title.cstring, nil, action, nil)
    for button in buttons:
        discard dialog.add_button(button.title.cstring, button.responseType.cint)
    let fileChooser = cast[PFileChooser](pointer(dialog))
    if defaultName.len > 0:
        gtk_file_chooser_set_current_name(fileChooser, defaultName.cstring)
    if defaultDir.len > 0:
        discard gtk_file_chooser_set_current_folder(fileChooser, defaultDir.cstring)
    fileChooser.addFilters(filters)
    var res = dialog.run()
    case res:
    of RESPONSE_ACCEPT, RESPONSE_YES, RESPONSE_APPLY:
        result = $fileChooser.get_filename()
    of RESPONSE_REJECT, RESPONSE_NO, RESPONSE_CANCEL, RESPONSE_CLOSE:
        result = ""
    else:
        result = ""
    dialog.destroy()
    while events_pending() > 0:
        discard main_iteration()

proc getWindowToolkitKind*(): WindowToolkitKind =
    return WindowToolkitKind.Gtk

proc callDialogFileOpen*(title: string, defaultDir: string = "", filters: openArray[(string, string)] = []): string =
    return callDialogFile(TFileChooserAction.FILE_CHOOSER_ACTION_OPEN, title, dialogFileOpenDefaultButtons, defaultDir = defaultDir, filters = filters)

proc callDialogFileOpenMultiple*(title: string, defaultDir: string = "", filters: openArray[(string, string)] = []): seq[string] =
    var dialog = file_chooser_dialog_new(title.cstring, nil, TFileChooserAction.FILE_CHOOSER_ACTION_OPEN, nil)
    for button in dialogFileOpenDefaultButtons:
        discard dialog.add_button(button.title.cstring, button.responseType.cint)
    let fileChooser = cast[PFileChooser](pointer(dialog))
    gtk_file_chooser_set_select_multiple(fileChooser, 1)
    if defaultDir.len > 0:
        discard gtk_file_chooser_set_current_folder(fileChooser, defaultDir.cstring)
    fileChooser.addFilters(filters)
    var res = dialog.run()
    if res in [RESPONSE_ACCEPT, RESPONSE_YES, RESPONSE_APPLY]:
        var node = cast[ptr GSListNode](gtk_file_chooser_get_filenames(fileChooser))
        while node != nil:
            result.add($cast[cstring](node.data))
            node = cast[ptr GSListNode](node.next)
    dialog.destroy()
    while events_pending() > 0:
        discard main_iteration()

proc callDialogFileSave*(title: string, defaultName: string = "", defaultDir: string = "", filters: openArray[(string, string)] = []): string =
    return callDialogFile(TFileChooserAction.FILE_CHOOSER_ACTION_SAVE, title, dialogFileSaveDefaultButtons, defaultName, defaultDir, filters)

proc callDialogFolderCreate*(title: string): string =
    return callDialogFile(TFileChooserAction.FILE_CHOOSER_ACTION_CREATE_FOLDER, title, dialogFolderCreateDefaultButtons)

proc callDialogFolderSelect*(title: string, defaultDir: string = ""): string =
    return callDialogFile(TFileChooserAction.FILE_CHOOSER_ACTION_SELECT_FOLDER, title, dialogFolderSelectDefaultButtons, defaultDir = defaultDir)