#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>

@interface VFAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *stateItem;
@property(nonatomic, strong) NSMenuItem *shortcutItem;
@property(nonatomic, strong) NSTask *backendTask;
@property(nonatomic, strong) NSTask *ollamaTask;
@property(nonatomic, assign) EventHotKeyRef hotKeyRef;
@property(nonatomic, assign) EventHandlerRef hotKeyHandler;
@property(nonatomic, copy) NSString *selectedText;
@property(nonatomic, copy) NSString *hotkeyDisplay;
@property(nonatomic, assign) BOOL listening;
@property(nonatomic, assign) BOOL hotkeyReady;
@property(nonatomic, assign) BOOL busy;
@property(nonatomic, assign) BOOL startRequestInFlight;
@property(nonatomic, assign) BOOL stopRequested;
@property(nonatomic, assign) BOOL lastInjectionCopied;
@property(nonatomic, strong) NSTimer *recordingWatchdog;
@end

static OSStatus VFHotKeyCallback(
    EventHandlerCallRef nextHandler,
    EventRef event,
    void *userInfo
) {
    (void)nextHandler;
    VFAppDelegate *delegate = (__bridge VFAppDelegate *)userInfo;
    UInt32 kind = GetEventKind(event);
    if (kind == kEventHotKeyPressed && !delegate.busy) {
        [delegate performSelector:@selector(beginListening)];
    } else if (kind == kEventHotKeyReleased && delegate.listening) {
        [delegate performSelector:@selector(finishListening)];
    }
    return noErr;
}

@implementation VFAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [self configureMenu];
    [self updateState:@"● Starting" error:nil];
    [self requestAccessibility];
    [self startOllamaIfPresent];
    [self startBackend];
    [self installHotkey];
    [self waitForBackend:20];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    if (self.backendTask.running) {
        [self.backendTask terminate];
    }
    if (self.ollamaTask.running) {
        [self.ollamaTask terminate];
    }
    if (self.hotKeyRef) {
        UnregisterEventHotKey(self.hotKeyRef);
    }
    if (self.hotKeyHandler) {
        RemoveEventHandler(self.hotKeyHandler);
    }
    [self.recordingWatchdog invalidate];
}

- (void)configureMenu {
    self.statusItem = [
        NSStatusBar.systemStatusBar
        statusItemWithLength:NSVariableStatusItemLength
    ];
    self.statusItem.button.title = @"🎙 VoiceForge";
    NSMenu *menu = [[NSMenu alloc] init];
    self.stateItem = [[NSMenuItem alloc] initWithTitle:@"● Starting"
        action:nil keyEquivalent:@""];
    self.stateItem.enabled = NO;
    [menu addItem:self.stateItem];
    [menu addItem:NSMenuItem.separatorItem];

    self.hotkeyDisplay = @"⌘⇧Space";
    self.shortcutItem = [[NSMenuItem alloc]
        initWithTitle:@"按住 ⌘⇧Space 讲话" action:nil keyEquivalent:@""];
    self.shortcutItem.enabled = NO;
    [menu addItem:self.shortcutItem];
    for (NSString *label in @[
        @"ASR：SenseVoiceSmall（本地）",
        @"语言：中文"
    ]) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:label action:nil keyEquivalent:@""];
        item.enabled = NO;
        [menu addItem:item];
    }
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"打开设置文件"
        action:@selector(openSettings) keyEquivalent:@","]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"重新加载快捷键"
        action:@selector(reloadHotkey) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"打开数据目录"
        action:@selector(openDataDirectory) keyEquivalent:@""]];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"退出 VoiceForge"
        action:@selector(terminate:) keyEquivalent:@"q"]];
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action != nil) {
            item.target = [item.title hasPrefix:@"退出"]
                ? NSApplication.sharedApplication
                : self;
        }
    }
    self.statusItem.menu = menu;
}

- (void)requestAccessibility {
    NSDictionary *options = @{
        (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES
    };
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (NSURL *)projectRoot {
    NSURL *config = [[NSFileManager.defaultManager homeDirectoryForCurrentUser]
        URLByAppendingPathComponent:
            @"Library/Application Support/VoiceForge/project-root"];
    NSString *value = [NSString stringWithContentsOfURL:config
        encoding:NSUTF8StringEncoding error:nil];
    value = [value stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (value.length == 0) {
        return nil;
    }
    return [NSURL fileURLWithPath:value isDirectory:YES];
}

- (void)startBackend {
    NSURL *root = self.projectRoot;
    if (root == nil) {
        return;
    }
    NSURL *python = [root URLByAppendingPathComponent:@".venv/bin/python"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:python.path]) {
        return;
    }
    NSURL *dataDirectory = [root URLByAppendingPathComponent:@"data"];
    [NSFileManager.defaultManager createDirectoryAtURL:dataDirectory
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *logURL = [dataDirectory URLByAppendingPathComponent:@"backend.log"];
    if (![NSFileManager.defaultManager fileExistsAtPath:logURL.path]) {
        [NSData.data writeToURL:logURL atomically:YES];
    }
    NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logURL.path];
    [log seekToEndOfFile];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = python;
    task.arguments = @[@"-m", @"backend.main", @"serve"];
    task.currentDirectoryURL = root;
    task.standardOutput = log;
    task.standardError = log;
    NSError *error = nil;
    if ([task launchAndReturnError:&error]) {
        self.backendTask = task;
    } else {
        [self updateState:@"● Backend Error" error:error.localizedDescription];
    }
}

- (void)startOllamaIfPresent {
    NSURL *binary = [[NSFileManager.defaultManager homeDirectoryForCurrentUser]
        URLByAppendingPathComponent:
            @"Applications/Ollama.app/Contents/Resources/ollama"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:binary.path]) {
        return;
    }
    NSURL *root = self.projectRoot;
    NSURL *logURL = [root URLByAppendingPathComponent:@"data/ollama.log"];
    [NSFileManager.defaultManager createDirectoryAtURL:
        [logURL URLByDeletingLastPathComponent]
        withIntermediateDirectories:YES attributes:nil error:nil];
    if (![NSFileManager.defaultManager fileExistsAtPath:logURL.path]) {
        [NSData.data writeToURL:logURL atomically:YES];
    }
    NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logURL.path];
    [log seekToEndOfFile];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = binary;
    task.arguments = @[@"serve"];
    task.standardOutput = log;
    task.standardError = log;
    NSError *error = nil;
    if ([task launchAndReturnError:&error]) {
        self.ollamaTask = task;
    }
}

- (void)installHotkey {
    self.hotkeyReady = NO;
    if (self.hotKeyRef) {
        UnregisterEventHotKey(self.hotKeyRef);
        self.hotKeyRef = NULL;
    }
    if (!self.hotKeyHandler) {
        EventTypeSpec eventTypes[] = {
            { kEventClassKeyboard, kEventHotKeyPressed },
            { kEventClassKeyboard, kEventHotKeyReleased }
        };
        OSStatus handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            VFHotKeyCallback,
            2,
            eventTypes,
            (__bridge void *)self,
            &_hotKeyHandler
        );
        if (handlerStatus != noErr) {
            [self updateState:@"● Hotkey Error"
                error:[NSString stringWithFormat:
                    @"无法安装系统热键处理器（%d）。", (int)handlerStatus]];
            return;
        }
    }

    UInt32 keyCode = 0;
    UInt32 modifiers = 0;
    NSString *display = nil;
    NSString *parseError = nil;
    NSString *spec = [self configuredHotkey];
    if (![self parseHotkeySpec:spec keyCode:&keyCode modifiers:&modifiers
        display:&display error:&parseError]) {
        [self updateState:@"● Hotkey Error" error:parseError];
        return;
    }

    EventHotKeyID hotKeyID = {
        .signature = 'VFRG',
        .id = 1
    };
    OSStatus registerStatus = RegisterEventHotKey(
        keyCode,
        modifiers,
        hotKeyID,
        GetApplicationEventTarget(),
        0,
        &_hotKeyRef
    );
    if (registerStatus != noErr) {
        [self updateState:@"● Hotkey Error"
            error:[NSString stringWithFormat:
                @"%@ 注册失败（%d），可能与其他应用冲突。",
                display, (int)registerStatus]];
        return;
    }
    self.hotkeyDisplay = display;
    self.shortcutItem.title = [NSString stringWithFormat:
        @"按住 %@ 讲话", display];
    self.hotkeyReady = YES;
    [self appendHotkeyLog:[NSString stringWithFormat:
        @"carbon hotkey registered: %@ (%@)", display, spec]];
}

- (NSString *)configuredHotkey {
    NSURL *root = self.projectRoot;
    NSURL *settings = [root URLByAppendingPathComponent:@".env"];
    NSString *contents = [NSString stringWithContentsOfURL:settings
        encoding:NSUTF8StringEncoding error:nil];
    for (NSString *rawLine in
         [contents componentsSeparatedByCharactersInSet:
            NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([line hasPrefix:@"VOICEFORGE_HOTKEY="]) {
            NSString *value = [line substringFromIndex:
                [@"VOICEFORGE_HOTKEY=" length]];
            value = [value stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (([value hasPrefix:@"\""] && [value hasSuffix:@"\""]) ||
                ([value hasPrefix:@"'"] && [value hasSuffix:@"'"])) {
                value = [value substringWithRange:
                    NSMakeRange(1, value.length - 2)];
            }
            if (value.length > 0) return value;
        }
    }
    return @"command+shift+space";
}

- (BOOL)parseHotkeySpec:(NSString *)spec
                keyCode:(UInt32 *)keyCode
              modifiers:(UInt32 *)modifiers
                 display:(NSString **)display
                   error:(NSString **)error {
    NSString *normalized = [[spec lowercaseString]
        stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSArray<NSString *> *parts = [normalized componentsSeparatedByString:@"+"];
    UInt32 parsedModifiers = 0;
    NSString *keyName = nil;
    for (NSString *part in parts) {
        if ([part isEqualToString:@"command"] || [part isEqualToString:@"cmd"]) {
            parsedModifiers |= cmdKey;
        } else if ([part isEqualToString:@"shift"]) {
            parsedModifiers |= shiftKey;
        } else if ([part isEqualToString:@"option"] ||
                   [part isEqualToString:@"alt"]) {
            parsedModifiers |= optionKey;
        } else if ([part isEqualToString:@"control"] ||
                   [part isEqualToString:@"ctrl"]) {
            parsedModifiers |= controlKey;
        } else if (part.length > 0 && keyName == nil) {
            keyName = part;
        } else {
            if (error) *error = [NSString stringWithFormat:
                @"快捷键格式无效：%@。示例：command+shift+space", spec];
            return NO;
        }
    }
    if (parsedModifiers == 0 || keyName.length == 0) {
        if (error) *error =
            @"快捷键必须包含至少一个修饰键和一个按键。";
        return NO;
    }

    static NSDictionary<NSString *, NSNumber *> *keyCodes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keyCodes = @{
            @"space": @(kVK_Space), @"return": @(kVK_Return),
            @"enter": @(kVK_Return), @"tab": @(kVK_Tab),
            @"escape": @(kVK_Escape), @"esc": @(kVK_Escape),
            @"a": @(kVK_ANSI_A), @"b": @(kVK_ANSI_B),
            @"c": @(kVK_ANSI_C), @"d": @(kVK_ANSI_D),
            @"e": @(kVK_ANSI_E), @"f": @(kVK_ANSI_F),
            @"g": @(kVK_ANSI_G), @"h": @(kVK_ANSI_H),
            @"i": @(kVK_ANSI_I), @"j": @(kVK_ANSI_J),
            @"k": @(kVK_ANSI_K), @"l": @(kVK_ANSI_L),
            @"m": @(kVK_ANSI_M), @"n": @(kVK_ANSI_N),
            @"o": @(kVK_ANSI_O), @"p": @(kVK_ANSI_P),
            @"q": @(kVK_ANSI_Q), @"r": @(kVK_ANSI_R),
            @"s": @(kVK_ANSI_S), @"t": @(kVK_ANSI_T),
            @"u": @(kVK_ANSI_U), @"v": @(kVK_ANSI_V),
            @"w": @(kVK_ANSI_W), @"x": @(kVK_ANSI_X),
            @"y": @(kVK_ANSI_Y), @"z": @(kVK_ANSI_Z),
            @"0": @(kVK_ANSI_0), @"1": @(kVK_ANSI_1),
            @"2": @(kVK_ANSI_2), @"3": @(kVK_ANSI_3),
            @"4": @(kVK_ANSI_4), @"5": @(kVK_ANSI_5),
            @"6": @(kVK_ANSI_6), @"7": @(kVK_ANSI_7),
            @"8": @(kVK_ANSI_8), @"9": @(kVK_ANSI_9)
        };
    });
    NSNumber *code = keyCodes[keyName];
    if (code == nil) {
        if (error) *error = [NSString stringWithFormat:
            @"暂不支持按键“%@”；可使用 Space、A-Z、0-9、Return、Tab 或 Escape。",
            keyName];
        return NO;
    }
    NSMutableString *label = [NSMutableString string];
    if (parsedModifiers & cmdKey) [label appendString:@"⌘"];
    if (parsedModifiers & shiftKey) [label appendString:@"⇧"];
    if (parsedModifiers & optionKey) [label appendString:@"⌥"];
    if (parsedModifiers & controlKey) [label appendString:@"⌃"];
    [label appendString:[keyName isEqualToString:@"space"]
        ? @"Space" : keyName.uppercaseString];
    *keyCode = code.unsignedIntValue;
    *modifiers = parsedModifiers;
    if (display) *display = label;
    return YES;
}

- (void)reloadHotkey {
    [self installHotkey];
    if (self.hotkeyReady) {
        [self updateState:@"● Ready" error:nil];
    }
}

- (void)appendHotkeyLog:(NSString *)message {
    NSURL *root = self.projectRoot;
    if (root == nil) return;
    NSURL *logURL = [root URLByAppendingPathComponent:@"data/hotkey.log"];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n",
        NSDate.date.description, message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (![NSFileManager.defaultManager fileExistsAtPath:logURL.path]) {
        [data writeToURL:logURL atomically:YES];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logURL.path];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

- (void)waitForBackend:(NSInteger)remaining {
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:8765/health"];
    NSURLSessionDataTask *task = [
        NSURLSession.sharedSession
        dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            (void)data;
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error == nil && status >= 200 &&
                    status < 300 && self.hotkeyReady) {
                    [self updateState:@"● Ready" error:nil];
                } else if (remaining > 0) {
                    dispatch_after(
                        dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                        dispatch_get_main_queue(),
                        ^{ [self waitForBackend:remaining - 1]; }
                    );
                } else {
                    [self updateState:@"● Backend Error"
                        error:error.localizedDescription ?: @"服务启动超时。"];
                }
            });
        }
    ];
    [task resume];
}

- (NSString *)currentSelection {
    AXUIElementRef system = AXUIElementCreateSystemWide();
    CFTypeRef focused = nil;
    AXError focusedError = AXUIElementCopyAttributeValue(
        system, kAXFocusedUIElementAttribute, &focused
    );
    CFRelease(system);
    if (focusedError != kAXErrorSuccess || focused == nil) {
        return nil;
    }
    CFTypeRef selection = nil;
    AXError selectionError = AXUIElementCopyAttributeValue(
        (AXUIElementRef)focused, kAXSelectedTextAttribute, &selection
    );
    CFRelease(focused);
    if (selectionError != kAXErrorSuccess || selection == nil) {
        return nil;
    }
    return CFBridgingRelease(selection);
}

- (void)beginListening {
    if (self.busy) {
        return;
    }
    self.busy = YES;
    self.listening = YES;
    self.startRequestInFlight = YES;
    self.stopRequested = NO;
    [self appendHotkeyLog:@"hotkey pressed"];
    [self.recordingWatchdog invalidate];
    self.recordingWatchdog = [NSTimer
        scheduledTimerWithTimeInterval:120
        target:self
        selector:@selector(finishListening)
        userInfo:nil
        repeats:NO
    ];
    self.selectedText = [self currentSelection];
    [self updateState:@"● Listening" error:nil];
    [self postPath:@"v1/recording/start" body:@{}
        completion:^(NSDictionary *result, NSError *error) {
            (void)result;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.startRequestInFlight = NO;
                if (error) {
                    self.listening = NO;
                    self.busy = NO;
                    self.stopRequested = NO;
                    [self.recordingWatchdog invalidate];
                    self.recordingWatchdog = nil;
                    [self appendHotkeyLog:[NSString stringWithFormat:
                        @"recording start error: %@",
                        error.localizedDescription]];
                    [self updateState:@"● Record Error"
                        error:error.localizedDescription];
                    return;
                }
                if (self.stopRequested) {
                    self.stopRequested = NO;
                    [self finishListening];
                }
            });
        }];
}

- (void)finishListening {
    if (!self.listening) {
        return;
    }
    if (self.startRequestInFlight) {
        self.stopRequested = YES;
        [self appendHotkeyLog:@"hotkey released; stop queued"];
        [self updateState:@"● Stopping" error:nil];
        return;
    }
    self.listening = NO;
    [self.recordingWatchdog invalidate];
    self.recordingWatchdog = nil;
    [self appendHotkeyLog:@"hotkey released"];
    [self updateState:@"● Processing" error:nil];
    NSDictionary *body = @{
        @"selected_text": self.selectedText ?: NSNull.null
    };
    [self postPath:@"v1/recording/stop" body:body
        completion:^(NSDictionary *result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    self.busy = NO;
                    [self appendHotkeyLog:[NSString stringWithFormat:
                        @"processing error: %@", error.localizedDescription]];
                    [self updateState:@"● Processing Error"
                        error:error.localizedDescription];
                    return;
                }
                NSString *text = result[@"text"];
                if ([self injectText:text]) {
                    self.busy = NO;
                    [self updateState:@"● Ready" error:nil];
                    NSString *application = NSWorkspace.sharedWorkspace
                        .frontmostApplication.localizedName ?: @"";
                    NSMutableDictionary *ack = [result mutableCopy];
                    ack[@"application"] = application;
                    [self postPath:@"v1/injection/completed"
                        body:ack completion:^(NSDictionary *r, NSError *e) {
                            (void)r; (void)e;
                        }];
                } else if (self.lastInjectionCopied) {
                    self.busy = NO;
                    [self appendHotkeyLog:
                        @"injection unavailable; copied to clipboard"];
                    [self updateState:@"● Copied"
                        error:@"结果已复制到剪贴板；请刷新 VoiceForge 的辅助功能授权以自动写入。"];
                } else {
                    self.busy = NO;
                    [self appendHotkeyLog:@"injection error"];
                    [self updateState:@"● Inject Error"
                        error:@"请授予 VoiceForge 辅助功能权限。"];
                }
            });
        }];
}

- (BOOL)injectText:(NSString *)text {
    self.lastInjectionCopied = NO;
    if (text.length == 0) {
        return NO;
    }
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSString *oldText = [pasteboard stringForType:NSPasteboardTypeString];
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
    NSInteger changeCount = pasteboard.changeCount;
    if (!AXIsProcessTrusted()) {
        self.lastInjectionCopied = YES;
        return NO;
    }

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    CGEventRef down = CGEventCreateKeyboardEvent(source, 9, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, 9, false);
    if (!source || !down || !up) {
        if (source) CFRelease(source);
        if (down) CFRelease(down);
        if (up) CFRelease(up);
        return NO;
    }
    CGEventSetFlags(down, kCGEventFlagMaskCommand);
    CGEventSetFlags(up, kCGEventFlagMaskCommand);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    CFRelease(source);

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 800 * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            if (pasteboard.changeCount == changeCount && oldText != nil) {
                [pasteboard clearContents];
                [pasteboard setString:oldText forType:NSPasteboardTypeString];
            }
        }
    );
    return YES;
}

- (void)postPath:(NSString *)path
            body:(NSDictionary *)body
      completion:(void (^)(NSDictionary *, NSError *))completion {
    NSString *urlString = [
        @"http://127.0.0.1:8765/"
        stringByAppendingString:path
    ];
    NSMutableURLRequest *request = [
        NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
    ];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body
        options:0 error:nil];
    request.timeoutInterval = 180;
    NSURLSessionDataTask *task = [
        NSURLSession.sharedSession
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            NSDictionary *json = data.length
                ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]
                : @{};
            if (error == nil && (status < 200 || status >= 300)) {
                NSString *detail = json[@"detail"] ?: [
                    NSString stringWithFormat:@"HTTP %ld", (long)status
                ];
                error = [NSError errorWithDomain:@"VoiceForge"
                    code:status
                    userInfo:@{NSLocalizedDescriptionKey: detail}];
            }
            completion(json ?: @{}, error);
        }
    ];
    [task resume];
}

- (void)updateState:(NSString *)state error:(NSString *)error {
    self.stateItem.title = state;
    self.statusItem.button.title = [state isEqualToString:@"● Ready"]
        ? @"🎙 VoiceForge"
        : [@"🎙 " stringByAppendingString:
            [state stringByReplacingOccurrencesOfString:@"● " withString:@""]];
    self.statusItem.button.toolTip = error ?: [NSString stringWithFormat:
        @"按住 %@ 讲话", self.hotkeyDisplay ?: @"⌘⇧Space"];
}

- (void)openSettings {
    NSURL *root = self.projectRoot;
    if (root == nil) return;
    NSURL *settings = [root URLByAppendingPathComponent:@".env"];
    [NSWorkspace.sharedWorkspace openURL:settings];
}

- (void)openDataDirectory {
    NSURL *root = self.projectRoot;
    if (root == nil) return;
    NSURL *data = [root URLByAppendingPathComponent:@"data"];
    [NSFileManager.defaultManager createDirectoryAtURL:data
        withIntermediateDirectories:YES attributes:nil error:nil];
    [NSWorkspace.sharedWorkspace openURL:data];
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        VFAppDelegate *delegate = [[VFAppDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [application run];
    }
    return 0;
}
