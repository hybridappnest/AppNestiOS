//
//  TConversationListViewModel.m
//  TXIMSDK_TUIKit_iOS
//
//  Created by annidyfeng on 2019/5/17.
//

#import "TConversationListViewModel.h"
#import "TUILocalStorage.h"
#import "TUIKit.h"
#import "ReactiveObjC/ReactiveObjC.h"
#import "MMLayout/UIView+MMLayout.h"
#import "TIMMessage+DataProvider.h"
#import "UIColor+TUIDarkMode.h"
#import "NSBundle+TUIKIT.h"
#import "TUIKitListenerManager.h"

@interface TConversationListViewModel ()
@property (nonatomic, assign) uint64_t nextSeq;
@property (nonatomic, assign) uint64_t isFinished;
@property (nonatomic, strong) NSMutableArray *localConvList;
@end

@implementation TConversationListViewModel

- (instancetype)init
{
    if (self = [super init]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onRefreshNotificationAdded:) name:TUIKitNotification_TIMRefreshListener_Add object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onRefreshNotificationChanged:) name:TUIKitNotification_TIMRefreshListener_Changed object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onGroupDismiss:) name:TUIKitNotification_onGroupDismissed object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onGroupRecycled:) name:TUIKitNotification_onGroupRecycled object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onKickOffFromGroup:) name:TUIKitNotification_onKickOffFromGroup object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onLeaveFromGroup:) name:TUIKitNotification_onLeaveFromGroup object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didTopConversationListChanged:) name:kTopConversationListChangedNotification object:nil];
        self.localConvList = [[NSMutableArray alloc] init];
        self.pagePullCount = 100;
        self.nextSeq = 0;
        self.isFinished = NO;
        [self loadConversation];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didTopConversationListChanged:(NSNotification *)no
{
    NSMutableArray *dataList = [NSMutableArray arrayWithArray:self.dataList];
    [self sortDataList:dataList];
    self.dataList = dataList;
}

- (void)onRefreshNotificationAdded:(NSNotification *)notify {
    // ????????????
    NSArray *convList = notify.object;
    [self updateConversation:convList];
}

- (void)onRefreshNotificationChanged:(NSNotification *)notify {
    // ????????????
    NSArray *convList = notify.object;
    [self updateConversation:convList];
}

- (void)loadConversation
{
    if (self.isFinished) {
        return;
    }
    @weakify(self)
    [[V2TIMManager sharedInstance] getConversationList:self.nextSeq count:self.pagePullCount succ:^(NSArray<V2TIMConversation *> *list, uint64_t nextSeq, BOOL isFinished) {
        @strongify(self)
        self.nextSeq = nextSeq;
        self.isFinished = isFinished;
        [self updateConversation:list];
    } fail:^(int code, NSString *msg) {
        self.isFinished = YES;
        NSLog(@"getConversationList failed, code:%d msg:%@", code, msg);
    }];
}

- (void)updateConversation:(NSArray *)convList
{
    // ?????? UI ????????????????????? UI ?????????????????????????????????????????????????????????????????????
    for (int i = 0 ; i < convList.count ; ++ i) {
        V2TIMConversation *conv = convList[i];
        BOOL isExit = NO;
        for (int j = 0; j < self.localConvList.count; ++ j) {
            V2TIMConversation *localConv = self.localConvList[j];
            if ([localConv.conversationID isEqualToString:conv.conversationID]) {
                [self.localConvList replaceObjectAtIndex:j withObject:conv];
                isExit = YES;
                break;
            }
        }
        if (!isExit) {
            [self.localConvList addObject:conv];
        }
    }
    // ?????? cell data
    NSMutableArray *dataList = [NSMutableArray array];
    for (V2TIMConversation *conv in self.localConvList) {
        // ????????????
        if ([self filteConversation:conv]) {
            continue;
        }
        
        // ??????cellData
        TUIConversationCellData *data = [[TUIConversationCellData alloc] init];
        data.conversationID = conv.conversationID;
        data.groupID = conv.groupID;
        data.groupType = conv.groupType;
        data.userID = conv.userID;
        data.title = conv.showName;
        data.faceUrl = conv.faceUrl;
        data.subTitle = [self getLastDisplayString:conv];
        data.atMsgSeqList = [self getGroupAtMsgSeqList:conv];
        data.time = [self getLastDisplayDate:conv];
        data.isOnTop = conv.isPinned;
        data.unreadCount = conv.unreadCount;
        data.draftText = conv.draftText;
        data.isNotDisturb = (conv.recvOpt == V2TIM_NOT_RECEIVE_MESSAGE);
        if (conv.type == V2TIM_C2C) {   // ???????????????????????????
            data.avatarImage = DefaultAvatarImage;
        } else {
            data.avatarImage = DefaultGroupAvatarImage;
        }
        
        [dataList addObject:data];
    }
    // UI ?????????????????? lastMessage ?????????????????????
    [self sortDataList:dataList];
    self.dataList = dataList;
}

- (BOOL)filteConversation:(V2TIMConversation *)conv
{
    // ??????AVChatRoom???????????????
    if ([conv.groupType isEqualToString:@"AVChatRoom"]) {
        return YES;
    }
    
    // ??????????????????
    if ([self getLastDisplayDate:conv] == nil) {
        if (conv.unreadCount != 0) {
            // ?????? ???????????????????????????data.time???nil?????????????????????????????????????????????lastMessage??????(v1conv???lastmessage)?????????????????????????????????????????????????????????????????????????????????
            // ????????????????????????????????????????????????
            NSString *userID = conv.userID;
            if (userID.length > 0) {
                [[V2TIMManager sharedInstance] markC2CMessageAsRead:userID succ:^{
                    
                } fail:^(int code, NSString *msg) {
                    
                }];
            }
            NSString *groupID = conv.groupID;
            if (groupID.length > 0) {
                [[V2TIMManager sharedInstance] markGroupMessageAsRead:groupID succ:^{
                    
                } fail:^(int code, NSString *msg) {
                    
                }];
            }
        }
        return YES;
    }
    
    return NO;
}

- (void)onGroupDismiss:(NSNotification *)no
{
    NSString *groupID = no.object;
    TUIConversationCellData *data = [self cellDataOf:groupID];
    if (data) {
        [THelper makeToast:[NSString stringWithFormat:TUILocalizableString(TUIKitGroupDismssTipsFormat), data.groupID]];
        [self removeData:data];
    }
}

- (void)onGroupRecycled:(NSNotification *)no
{
    NSString *groupID = no.object;
    TUIConversationCellData *data = [self cellDataOf:groupID];
    if (data) {
        [THelper makeToast:[NSString stringWithFormat:TUILocalizableString(TUIKitGroupRecycledTipsFormat), data.groupID]];
        [self removeData:data];
    }
}

- (void)onKickOffFromGroup:(NSNotification *)no
{
    NSString *groupID = no.object;
    TUIConversationCellData *data = [self cellDataOf:groupID];
    if (data) {
        [THelper makeToast:[NSString stringWithFormat:TUILocalizableString(TUIKitGroupKickOffTipsFormat), data.groupID]];
        [self removeData:data];
    }
}

- (void)onLeaveFromGroup:(NSNotification *)no
{
    NSString *groupID = no.object;
    TUIConversationCellData *data = [self cellDataOf:groupID];
    if (data) {
        [THelper makeToast:[NSString stringWithFormat:TUILocalizableString(TUIKitGroupDropoutTipsFormat), data.groupID]];
        [self removeData:data];
    }
}

- (NSMutableArray<NSNumber *> *)getGroupAtMsgSeqList:(V2TIMConversation *)conv {
    NSMutableArray *seqList = [NSMutableArray array];
    for (V2TIMGroupAtInfo *atInfo in conv.groupAtInfolist) {
        [seqList addObject:@(atInfo.seq)];
    }
    if (seqList.count > 0) {
        return seqList;
    }
    return nil;
}

- (NSString *)getGroupAtTipString:(V2TIMConversation *)conv {
    NSString *atTipsStr = @"";
    BOOL atMe = NO;
    BOOL atAll = NO;
    for (V2TIMGroupAtInfo *atInfo in conv.groupAtInfolist) {
        switch (atInfo.atType) {
            case V2TIM_AT_ME:
                atMe = YES;
                continue;;
            case V2TIM_AT_ALL:
                atAll = YES;
                continue;;
            case V2TIM_AT_ALL_AT_ME:
                atMe = YES;
                atAll = YES;
                continue;;
            default:
                continue;;
        }
    }
    if (atMe && !atAll) {
        atTipsStr = TUILocalizableString(TUIKitConversationTipsAtMe); // @"[??????@???]";
    }
    if (!atMe && atAll) {
        atTipsStr = TUILocalizableString(TUIKitConversationTipsAtAll); // @"[@?????????]";
    }
    if (atMe && atAll) {
        atTipsStr = TUILocalizableString(TUIKitConversationTipsAtMeAndAll); // @"[??????@???][@?????????]";
    }
    return atTipsStr;
}

- (NSMutableAttributedString *)getLastDisplayString:(V2TIMConversation *)conv
{
    NSString *lastMsgStr = @"";
    for (id<TUIConversationListControllerListener> delegate in [TUIKitListenerManager sharedInstance].convListeners) {
        if (delegate && [delegate respondsToSelector:@selector(getConversationDisplayString:)]) {
            lastMsgStr = [delegate getConversationDisplayString:conv];
            if (lastMsgStr.length > 0) {
                break;
            }
        }
    }
    if (lastMsgStr.length == 0) {
        lastMsgStr = [conv.lastMessage getDisplayString];
    }
    // ???????????? lastMsg ???????????????????????? nil
    if (lastMsgStr.length == 0 && conv.draftText.length == 0) {
        return nil;
    }
    NSString *atStr = [self getGroupAtTipString:conv];
    NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@",atStr]];
    NSDictionary *attributeDict = @{NSForegroundColorAttributeName:[UIColor d_systemRedColor]};
    [attributeString setAttributes:attributeDict range:NSMakeRange(0, attributeString.length)];
    
    if(conv.draftText.length > 0){
        [attributeString appendAttributedString:[[NSAttributedString alloc] initWithString:TUILocalizableString(TUIKitMessageTypeDraftFormat) attributes:@{NSForegroundColorAttributeName:[UIColor d_systemRedColor]}]];
        [attributeString appendAttributedString:[[NSAttributedString alloc] initWithString:conv.draftText attributes:@{NSForegroundColorAttributeName:[UIColor d_systemGrayColor]}]];
    } else {
        [attributeString appendAttributedString:[[NSAttributedString alloc] initWithString:lastMsgStr]];
    }
    return attributeString;
}

- (NSDate *)getLastDisplayDate:(V2TIMConversation *)conv
{
    if(conv.draftText.length > 0){
        return conv.draftTimestamp;
    }
    if (conv.lastMessage) {
        return conv.lastMessage.timestamp;
    }
    return [NSDate distantPast];
}

- (TUIConversationCellData *)cellDataOf:(NSString *)groupID
{
    for (TUIConversationCellData *data in self.dataList) {
        if ([data.groupID isEqualToString:groupID]) {
            return data;
        }
    }
    return nil;
}

- (void)sortDataList:(NSMutableArray<TUIConversationCellData *> *)dataList
{
#ifndef SDKPlaceTop
#define SDKPlaceTop   // SDK ????????????active_time??????IsPlaceHead??????????????????????????????TUIKit??????TUILocalStoreage??????toConversationList?????????????????????
#endif
    
#ifdef SDKPlaceTop
    // ?????????????????????
    // ??????????????????????????????????????????????????????
    // ???????????????????????????????????????
    [dataList sortUsingComparator:^NSComparisonResult(TUIConversationCellData *obj1, TUIConversationCellData *obj2) {
        if (obj1.isOnTop && !obj2.isOnTop) {
            return NSOrderedAscending;
        }else if (!obj1.isOnTop && obj2.isOnTop) {
            return NSOrderedDescending;
        }else {
            return [obj2.time compare:obj1.time];
        }
    }];
#else
    // ????????????????????????????????????
    [dataList sortUsingComparator:^NSComparisonResult(TUIConversationCellData *obj1, TUIConversationCellData *obj2) {
        return [obj2.time compare:obj1.time];
    }];

    // ?????????????????????????????????
    NSArray *topList = [[TUILocalStorage sharedInstance] topConversationList];
    int existTopListSize = 0;
    for (NSString *convID in topList) {
        int userIdx = -1;
        for (int i = 0; i < dataList.count; i++) {
            if ([dataList[i].conversationID isEqualToString:convID]) {
                userIdx = i;
                dataList[i].isOnTop = YES;
                break;
            }
        }
        if (userIdx >= 0 && userIdx != existTopListSize) {
            TUIConversationCellData *data = dataList[userIdx];
            [dataList removeObjectAtIndex:userIdx];
            [dataList insertObject:data atIndex:existTopListSize];
            existTopListSize++;
        }
    }
#endif
}

- (void)removeData:(TUIConversationCellData *)data
{
    NSMutableArray *list = [NSMutableArray arrayWithArray:self.dataList];
    [list removeObject:data];
    self.dataList = list;
    for (V2TIMConversation *conv in self.localConvList) {
        if ([conv.conversationID isEqualToString:data.conversationID]) {
            [self.localConvList removeObject:conv];
            break;
        }
    }
    [[V2TIMManager sharedInstance] deleteConversation:data.conversationID succ:nil fail:nil];
}
@end
