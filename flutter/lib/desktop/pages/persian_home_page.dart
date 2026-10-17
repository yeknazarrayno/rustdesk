import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/button.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/common/widgets/chat_page.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

const borderColor = Color(0xFF2F65BA);
const idColor = Color(0xFF00B6F0);

// Internet connectivity checker
class InternetConnectivityChecker {
  final List<String> hosts;
  final Duration interval;
  final Duration timeout;

  InternetConnectivityChecker({
    this.hosts = const ['raynodesk.ir:443', '1.1.1.1:443', '8.8.8.8:443'],
    this.interval = const Duration(seconds: 10),
    this.timeout = const Duration(seconds: 3),
  });

  final RxBool isConnected = true.obs;
  Timer? _timer;

  void startChecking() {
    updateConnectivity();
    _timer = Timer.periodic(interval, (_) => updateConnectivity());
  }

  void stopChecking() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> updateConnectivity() async {
    bool connected = false;
    for (final host in hosts) {
      try {
        final parts = host.split(':');
        final result = await Socket.connect(
          parts[0],
          int.parse(parts[1]),
          timeout: timeout,
        );
        await result.close();
        connected = true;
        break; // OR semantics: if any host responds, we're connected
      } catch (_) {
        // Continue to next host
      }
    }
    isConnected.value = connected;
  }
}

// Chat drawer overlay
class ChatDrawer extends StatefulWidget {
  final ChatModel chatModel;

  const ChatDrawer({Key? key, required this.chatModel}) : super(key: key);

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  ChatModel get chatModel => widget.chatModel;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            // Chat drawer header
            Container(
              height: 50,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          translate('Chat'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      // Close chat drawer
                      windowManager.show();
                    },
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            // Chat content area
            Expanded(
              child: ChatPage(chatModel: chatModel),
            ),
          ],
        ),
      ),
    );
  }
}

// Main Persian RTL Desktop Home Page
class PersianDesktopHomePage extends StatefulWidget {
  const PersianDesktopHomePage({Key? key}) : super(key: key);

  @override
  State<PersianDesktopHomePage> createState() => _PersianDesktopHomePageState();
}

class _PersianDesktopHomePageState extends State<PersianDesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();
  final _internetChecker = InternetConnectivityChecker();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;

  final RxBool _block = false.obs;
  final GlobalKey _childKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _internetChecker.startChecking();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
    });
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildBlock(
      child: buildLeftPane(context),
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      if (bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: loadPowered(context),
        ),
      // Logo
      buildLogo(context),
      // Page title with chat button
      buildPersianHeader(context),
      // Tip
      buildPersianTip(context),
      // ID Board
      if (!isOutgoingOnly) buildPersianIDBoard(context),
      // Password Board
      if (!isOutgoingOnly) buildPersianPasswordBoard(context),
      // Status section
      buildPersianStatusSection(context),
      // Help Cards
      FutureBuilder<Widget>(
        future: Future.value(
            Obx(() => buildHelpCards(stateGlobal.updateUrl.value))),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
    ];
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        color: Theme.of(context).colorScheme.background,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _leftPaneScrollController,
                child: Column(
                  key: _childKey,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  buildLogo(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Image.asset(
        'assets/logo.png',
        width: 180,
        height: 180,
      ),
    ).marginOnly(top: 20, bottom: 10);
  }

  buildPersianHeader(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Page title
          Text(
            translate("ID and Password"),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textColor?.withOpacity(0.9),
            ),
          ).marginOnly(left: 10),
          // Chat button
          GestureDetector(
            onTap: () {
              // Show chat drawer as overlay
              showChatDrawer(context);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chat_bubble, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    translate("Chat"),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  buildPersianTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOutgoingOnly)
            Align(
              alignment: Alignment.topRight,
              child: Text(
                translate("Your Desktop"),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          const SizedBox(height: 10),
          if (!isOutgoingOnly)
            Text(
              translate("desk_tip"),
              overflow: TextOverflow.clip,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ).marginOnly(top: 5),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ).marginOnly(top: 5),
        ],
      ),
    );
  }

  buildPersianIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Title
          Text(
            translate("ID"),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textColor?.withOpacity(0.7),
            ),
          ).marginOnly(bottom: 8),
          // ID Value
          GestureDetector(
            onDoubleTap: () {
              Clipboard.setData(
                  ClipboardData(text: model.serverId.text));
              showToast(translate("Copied"));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: idColor.withOpacity(0.5)),
              ),
              child: TextFormField(
                controller: model.serverId,
                readOnly: true,
                textAlign: TextAlign.left,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: idColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  buildPersianPasswordBoard(BuildContext context) {
    final model = gFFI.serverModel;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.3)),
      ),
      child: Consumer<ServerModel>(
        builder: (context, model, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Title
              Text(
                translate("One-time Password"),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor?.withOpacity(0.7),
                ),
              ).marginOnly(bottom: 8),
              // Password
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: () {
                        if (showOneTime) {
                          Clipboard.setData(
                              ClipboardData(text: model.serverPasswd.text));
                          showToast(translate("Copied"));
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: MyTheme.accent.withOpacity(0.5)),
                        ),
                        child: TextFormField(
                          controller: model.serverPasswd,
                          readOnly: true,
                          textAlign: TextAlign.left,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: MyTheme.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showOneTime) ...[
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: () => bind.mainUpdateTemporaryPassword(),
                      icon: const Icon(Icons.refresh, color: MyTheme.accent, size: 24),
                    ).marginOnly(right: 8, top: 4),
                  ],
                  if (!bind.isDisableSettings())
                    IconButton(
                      onPressed: () => DesktopSettingPage.switch2page(SettingsTabKey.general),
                      icon: const Icon(Icons.edit, color: MyTheme.accent, size: 24),
                    ).marginOnly(right: 8, top: 4),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  buildPersianStatusSection(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Status Title
          Row(
            mainAxisAlignment:
                rtl ? MainAxisAlignment.start : MainAxisAlignment.start,
            children: [
              Text(
                translate("Status"),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ).marginOnly(bottom: 10),
          // Server and Internet Status dots
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Server Status
              Expanded(
                child: buildStatusDot(
                  context,
                  title: translate("Server"),
                  isConnected: stateGlobal.svcStatus.value == SvcStatus.ready,
                  isConnecting: stateGlobal.svcStatus.value == SvcStatus.connecting,
                  isDisconnected: stateGlobal.svcStatus.value == SvcStatus.notReady,
                  dotColor: stateGlobal.svcStatus.value == SvcStatus.ready
                      ? const Color(0xFF00B6F0) // idColor
                      : stateGlobal.svcStatus.value == SvcStatus.connecting
                          ? kColorWarn
                          : kColorWarn,
                ),
              ),
              // Internet Status
              Expanded(
                child: buildStatusDot(
                  context,
                  title: translate("Internet"),
                  isConnected: _internetChecker.isConnected.value,
                  isConnecting: false,
                  isDisconnected: !_internetChecker.isConnected.value && _internetChecker.isConnected.value != null,
                  dotColor: _internetChecker.isConnected.value
                      ? const Color(0xFF00B6F0)
                      : kColorWarn,
                ),
              ),
            ],
          ).marginOnly(bottom: 10),
          // Status descriptions
          Row(
            mainAxisAlignment: rtl ? MainAxisAlignment.end : MainAxisAlignment.spaceBetween,
            children: [
              // Server status description
              buildStatusDescription(
                context,
                status: stateGlobal.svcStatus.value == SvcStatus.ready
                    ? translate("Ready")
                    : stateGlobal.svcStatus.value == SvcStatus.connecting
                        ? translate("connecting_status")
                        : translate("not_ready_status"),
              ),
              // Internet status description
              buildStatusDescription(
                context,
                status: _internetChecker.isConnected.value
                    ? translate("Connected")
                    : translate("Disconnected"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  buildStatusDot(
    BuildContext context, {
    required String title,
    required bool isConnected,
    required bool isConnecting,
    required bool isDisconnected,
    required Color dotColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Dot
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: dotColor.withOpacity(0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Title
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  buildStatusDescription(BuildContext context, {required String status}) {
    return Text(
      status,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5),
      ),
      textAlign: TextAlign.right,
    ).marginOnly(top: 4);
  }

  showChatDrawer(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Container(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 600 : double.infinity,
            maxHeight: isDesktop ? 500 : double.infinity,
          ),
          child: ChatDrawer(chatModel: gFFI.chatModel),
        );
      },
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://rustdesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          // macOS shows the request prompt only once per app, so later
          // presses would do nothing without opening the settings pane.
          launchUrl(Uri.parse(
              'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'));
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _internetChecker.stopChecking();
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }
}