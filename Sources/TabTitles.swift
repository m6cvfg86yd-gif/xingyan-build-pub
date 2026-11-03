import SwiftUI

extension C {
    static var tabText0: String {
        Lang.isRussian ? Tr(C.tabTitle0) : (Lang.isEnglish ? UIConfig.text("tabTitle0en", "Chats") : C.tabTitle0)
    }
    static var tabText1: String {
        Lang.isRussian ? Tr(C.tabTitle1) : (Lang.isEnglish ? UIConfig.text("tabTitle1en", "Contacts") : C.tabTitle1)
    }
    static var tabText2: String {
        Lang.isRussian ? Tr(C.tabTitle2) : (Lang.isEnglish ? UIConfig.text("tabTitle2en", "Discover") : C.tabTitle2)
    }
    static var tabText3: String {
        Lang.isRussian ? Tr(C.tabTitle3) : (Lang.isEnglish ? UIConfig.text("tabTitle3en", "Me") : C.tabTitle3)
    }
}
