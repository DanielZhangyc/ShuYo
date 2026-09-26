/// 企业微信扫码登录相关的固定参数。
///
/// 数值来源于上海大学统一身份认证（newsso）前端 bundle 中的企微
/// `WwLogin` SDK 渲染参数。若学校侧变更，需要同步更新这里。
class WeComConstants {
  const WeComConstants._();

  /// 上海大学企业微信自建应用 appid。
  static const appId = 'wxa8dea949443de641';

  /// 上海大学企业微信自建应用 agentid。
  static const agentId = '1000059';

  /// 企微扫码确认回调地址（newsso 侧的 /oauth/wecom/qrcode）。
  static const redirectUri = 'https://newsso.shu.edu.cn/oauth/wecom/qrcode';

  /// 企微扫码会话页面（返回 HTML，内嵌 `qrImg?key=<key>`）。
  static const qrConnectBase =
      'https://open.work.weixin.qq.com/wwopen/sso/qrConnect';

  /// 二维码图片地址。
  static const qrImgBase = 'https://open.work.weixin.qq.com/wwopen/sso/qrImg';

  /// 扫码后企微客户端打开的确认页地址。
  static const confirmBase =
      'https://open.work.weixin.qq.com/wwopen/sso/confirm2';

  /// 扫码状态长轮询地址（JSONP）。
  static const longPollBase =
      'https://open.work.weixin.qq.com/wwopen/sso/l/qrConnect';

  /// 企微客户端协议：在企微内拉起内置浏览器打开指定 URL。
  ///
  /// 来源：企微官方 confirm2 页面内联脚本，原文为
  /// `launchWWByScheme("wxwork://sso/jump?url=" + encodeURIComponent(confirm2_url))`。
  static const schemeJumpBase = 'wxwork://sso/jump?url=';

  /// 承载企微扫码会话的域名，用于构造正确的 Referer/Origin。
  static const weComHost = 'open.work.weixin.qq.com';

  /// 统一身份认证（SSO）站点，`authorize` 与业务系统回调都在这里。
  static const ssoBase = 'https://newsso.shu.edu.cn';

  /// 论坛走的是这个 SSO 域名（与 [ssoBase] 同源后端，但 cookie 按 host 隔离）。
  static const forumSsoHost = 'oauth.shu.edu.cn';

  /// WebVPN 模式下论坛 OAuth 经过的代理 SSO 域名。
  ///
  /// Android WebView 不会把 [ssoBase] 的 host-only Cookie 发送给该域名，
  /// 因此企微换取的 `SHU_OAUTH2` 需要另外写入这个 host。
  static const forumWebVpnSsoHost =
      'https-oauth-shu-edu-cn-443.webvpn.shu.edu.cn';

  /// WebVPN OAuth 握手使用的固定端点。
  static const webVpnBase = 'https://webvpn.shu.edu.cn';
  static const webVpnCallback = '$webVpnBase/callback/oauth2';
  static const webVpnLanding = '$webVpnBase/site-nav/';
  static const webVpnNewssoProxyHost =
      'https-newsso-shu-edu-cn-443.webvpn.shu.edu.cn';
  static const webVpnExternalIdFallback = 'YJrvSXWl';

  /// OAuth 授权端点路径。
  static const authorizePath = '/oauth/authorize';

  /// SSO 判定「未登录」时跳转的登录页路径片段。
  static const loginPathMarker = '/oauth2/login/';

  /// SSO 会话 Cookie 名。
  static const sessionCookieName = 'SHU_OAUTH2';
}

/// 扫码登录后要登录的目标业务系统。
///
/// 注意：企微扫码换取 SSO 会话时用的 `state` **始终是教务系统参数**
/// （见 `WeComAuthTarget.academic`），与这里的目标系统无关；目标系统只影响
/// SSO 会话建立之后的 `authorize` 阶段。
class WeComOAuthTarget {
  const WeComOAuthTarget({
    required this.kind,
    required this.clientId,
    required this.clientName,
    required this.scope,
    required this.redirectUri,
    this.stateBootstrapUrl,
    this.generateState = false,
  });

  /// 本科生教务系统（jwxt）：授权请求不带 state，需自行生成随机值防 CSRF。
  static const academic = WeComOAuthTarget(
    kind: WeComOAuthTargetKind.academic,
    clientId: 'Km5t225E8KECKQ6ZDm5K2P6aS2459Cua',
    clientName: '本科生教务系统',
    scope: 'jw',
    redirectUri: 'https://jwxt.shu.edu.cn/sso/shulogin',
    generateState: true,
  );

  /// 上大论坛（乐乎社区，bbs）：必须先向它自己要一个 state，再改走 SSO 授权。
  static const forum = WeComOAuthTarget(
    kind: WeComOAuthTargetKind.forum,
    clientId: 'vp8G2H42GGE86LP822LHF6Hs7f46483H',
    clientName: '上大bbs (乐乎社区)',
    scope: '',
    redirectUri: 'https://bbs.shu.edu.cn/auth/oauth2_basic/callback',
    stateBootstrapUrl: 'https://bbs.shu.edu.cn/auth/oauth2_basic',
  );

  /// WebVPN 需要在 OAuth 授权后调用 `auth/finish`，不能按通用
  /// callback 流程处理。
  static const webVpn = WeComOAuthTarget(
    kind: WeComOAuthTargetKind.webVpn,
    clientId: 'nn7sbb22j2tKE100T024tEp42777p755',
    clientName: 'WebVPN 访问控制系统',
    scope: '',
    redirectUri: WeComConstants.webVpnCallback,
  );

  final WeComOAuthTargetKind kind;

  final String clientId;
  final String clientName;
  final String scope;
  final String redirectUri;

  /// 需要先访问该地址，从它的 302 Location 里取出 `state`。
  /// 为空表示不需要预热。
  final String? stateBootstrapUrl;

  /// 为 true 时由本地生成随机 state。
  final bool generateState;

  /// 供 [WeComAuthService.encodeOAuthParams] 编码为 `state` 的原始参数。
  Map<String, String> toParams() => {
        'responseType': 'code',
        'clientId': clientId,
        'clientName': clientName,
        'scope': scope,
        'redirectUri': redirectUri,
        'state': '',
      };
}

enum WeComOAuthTargetKind { academic, forum, webVpn }
