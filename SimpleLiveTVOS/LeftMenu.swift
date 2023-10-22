//
//  LeftMenu.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/7/3.
//

import SwiftUI
import Kingfisher
import GameController

enum LiveType: String,Codable {
    case bilibili = "0",
         huya = "1",
         douyin = "2",
         douyu = "3",
         qie = "4"
}

struct LeftMenu: View {
    
    var liveType: LiveType
    @Binding var size: CGFloat
    @Binding var currentIndex: Int
    @Binding var isShowSubList: Bool
    @State private var mainList = [BilibiliMainListModel]()
    @State private var douyinMainList = [DouyinCategoryData]()
    @State private var douyuMainList = [DouyuMainListModel]()
    @State private var huyaMainList = [HuyaMainListModel]()
    @State private var menuImg = ""
    var leftMenuDidClick: (Int, Int, Any) -> Void = { _,_,_   in }
    @State private var firstLoad = false

    var body : some View {
       
        List(getList(liveType: self.liveType).indices, id: \.self, rowContent: { index in
            Section {
                Button(action: {
                    currentIndex = index
                    isShowSubList.toggle()
                }, label: {
                    if size == leftMenuHighLightStateWidth {
                        HStack(spacing: 30 ) {
                            Image(self.menuImg)
                                .resizable()
                                .frame(width: 40, height: 40)
                            if liveType == .bilibili {
                                Text(mainList[index].name)
//                                    .padding(.leading, -25)
                                    .font(.system(size: 25))
                            }else if liveType == .douyin {
                                Text(douyinMainList[index].partition.title)
//                                    .padding(.leading, -25)
                                    .font(.system(size: 25))
                            }else if liveType == .douyu {
                                Text(douyuMainList[index].name)
                                    .font(.system(size: 25))
                            }else if liveType == .huya {
                                Text(huyaMainList[index].name)
                                    .font(.system(size: 25))
                            }
                        }
                        .frame(width: size - 80,height: 100)
                        
                    }else {
                        VStack {
                            Image(self.menuImg)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                            if liveType == .bilibili {
                                Text(mainList[index].name)
                                    .font(.system(size: 20))
                            }else if liveType == .douyin {
                                Text(douyinMainList[index].partition.title)
                                    .font(.system(size: 20))
                            }else if liveType == .douyu {
                                Text(douyuMainList[index].name)
                                    .font(.system(size: 20))
                            }else if liveType == .huya {
                                Text(huyaMainList[index].name)
                                    .font(.system(size: 20))
                            }
                        }
                        .frame(width: size - 30,height: 100)
                    }
                    
                })
                .buttonStyle(CardButtonStyle())
                if currentIndex == index && isShowSubList {
                    ForEach(getSubList(liveType: liveType, index: index).indices, id: \.self) { subIndex in
                        Button(action: {
                            getCategoryRooms(subIndex: subIndex)
                        }, label: {
                            HStack {
                                if liveType == .bilibili {
                                    KFImage(URL(string: (mainList[index].list ?? [])[subIndex].pic))
                                        .resizable()
                                        .frame(width: 30, height: 30)
                                        .padding(.leading, 20)

                                    Text((mainList[index].list ?? [])[subIndex].name)
                                        .font(.system(size: 22))
                                        .padding(.trailing, 20)
                                        .padding(.leading, -40)
                                }else if liveType == .douyin {
                                    Image(self.menuImg)
                                        .resizable()
                                        .frame(width: 30, height: 30)
                                        .padding(.leading, 20)

                                    Text(douyinMainList[index].sub_partition[subIndex].partition.title)
                                        .font(.system(size: 22))
                                        .padding(.trailing, 20)
                                        .padding(.leading, -40)
                                }else if liveType == .douyu {
                                    
                                    KFImage(URL(string: douyuMainList[index].list[subIndex].squareIconUrlW))
                                        .resizable()
                                        .frame(width: 30, height: 30)
                                        .padding(.leading, 20)

                                    Text(douyuMainList[index].list[subIndex].cname2)
                                        .font(.system(size: 22))
                                        .padding(.trailing, 20)
                                        .padding(.leading, -40)
                                }else if liveType == .huya {
                                    
                                    KFImage(URL(string: huyaMainList[index].list[subIndex].pic))
                                        .resizable()
                                        .frame(width: 30, height: 30)
                                        .padding(.leading, 20)

                                    Text(huyaMainList[index].list[subIndex].gameFullName)
                                        .font(.system(size: 22))
                                        .padding(.trailing, 20)
                                        .padding(.leading, -40)
                                }
   
                            }
                            .frame(width: size - 60, height: 50)
                        })
                        .buttonStyle(CardButtonStyle())
                
     
                    }
                }
            }
            .padding(.leading, size == leftMenuHighLightStateWidth ? 20 : 0)
            .padding(.top, 5)
            .padding(.bottom, 5)
        })
        .onAppear {
            Task {
                if firstLoad == true {
                    return;
                }
                switch self.liveType {
                    case .bilibili:
                        self.menuImg = "bilibili"
                    case .douyu:
                        self.menuImg = "douyu"
                    case .huya:
                        self.menuImg = "huya"
                    default:
                        self.menuImg = "douyin"
                }
                if liveType == .bilibili {
                    self.mainList = try await Bilibili.getBiliBiliList().data
                    if self.mainList.first?.list?.count ?? 0 > 0 {
                        let category = self.mainList.first?.list?.first
                        self.leftMenuDidClick(0, 0, category!)
                    }
                }else if liveType == .douyin {
                    self.douyinMainList = try await Douyin.getDouyinList()
                    if self.douyinMainList.count > 0 {
                        let category = self.douyinMainList.first
                        self.leftMenuDidClick(0, 0, category!)
                    }
                }else if liveType == .douyu {
                    self.douyuMainList = [
                        DouyuMainListModel(id: "PCgame", name: "网游竞技", list:[]),
                        DouyuMainListModel(id: "djry", name: "单机热游", list:[]),
                        DouyuMainListModel(id: "syxx", name: "手游休闲", list:[]),
                        DouyuMainListModel(id: "yl", name: "娱乐天地", list:[]),
                        DouyuMainListModel(id: "yz", name: "颜值", list:[]),
                        DouyuMainListModel(id: "kjwh", name: "科技文化", list:[]),
                        DouyuMainListModel(id: "yp", name: "语言互动", list:[]),
                    ]
                    for i in 0..<douyuMainList.count {
                        let res = try await Douyu.getCategoryList(id: self.douyuMainList[i].id)
                        self.douyuMainList[i].list = res
                    }
                    if self.douyuMainList.count > 0 {
                        self.leftMenuDidClick(0, 0, self.douyuMainList.first!.list.first!)
                    }
                }else if liveType == .huya {
                    huyaMainList = [
                        HuyaMainListModel(id: "1", name: "网游", list: []),
                        HuyaMainListModel(id: "2", name: "单机", list: []),
                        HuyaMainListModel(id: "8", name: "娱乐", list: []),
                        HuyaMainListModel(id: "3", name: "手游", list: []),
                    ]
                    for i in 0..<huyaMainList.count  {
                        let res = try await Huya.getHuyaSubList(bussType: huyaMainList[i].id)
                        huyaMainList[i].list = res.data
                        print(huyaMainList[i].list)
                    }
                    if huyaMainList.count > 0 {
                        self.leftMenuDidClick(0, 0, self.huyaMainList.first!.list.first!)
                    }
                }
                firstLoad = true
            }
        }
        .frame(width: size)
        .padding(.top, 30)
    }
    
    func getCategoryRooms(subIndex: Int) {
        if self.liveType == .bilibili {
            let category = self.mainList[currentIndex].list?[subIndex]
            self.leftMenuDidClick(currentIndex, subIndex, category!)
        }else if self.liveType == .douyin {
            let category = self.douyinMainList[currentIndex].sub_partition[subIndex]
            self.leftMenuDidClick(0, 0, category)
        }else if self.liveType == .douyu {
            let category = self.douyuMainList[currentIndex].list[subIndex]
            self.leftMenuDidClick(0, 0, category)
        }else if self.liveType == .huya {
            let category = self.huyaMainList[currentIndex].list[subIndex]
            self.leftMenuDidClick(0, 0, category)
        }
    }
    
    func getList(liveType: LiveType) -> Array<Any> {
        if liveType == .bilibili {
            return mainList
        }else if liveType == .douyin {
            return douyinMainList
        }else if liveType == .douyu {
            return douyuMainList
        }else if liveType == .huya {
            return huyaMainList
        }else {
            return mainList
        }
    }
    
    func getSubList(liveType: LiveType, index: Int) -> Array<Any> {
        if liveType == .bilibili {
            return mainList[index].list ?? []
        }else if liveType == .douyin {
            return douyinMainList[index].sub_partition
        }else if liveType == .douyu {
            return douyuMainList[index].list
        }else if liveType == .huya {
            return huyaMainList[index].list
        }else {
            return mainList[index].list ?? []
        }
    }
}

