---
layout: geckoview
---
<h1> GeckoView API Changelog. </h1>
## v65
- Moved [`CompositorController`](../CompositorController.html),
  [`DynamicToolbarAnimator`](../DynamicToolbarAnimator.html),
  [`OverscrollEdgeEffect`](../OverscrollEdgeEffect),
  [`PanZoomController`](../PanZoomController) from `org.mozilla.gecko.gfx` to
  `org.mozilla.geckoview`
- Added `@UiThread`, `@AnyThread` annotations to several APIs
- Changed `GeckoRuntimeSettings#getLocale` to
  [`GeckoRuntimeSettings#getLocales`](../GeckoRuntimeSettings.html#getLocales--) and
  related APIs.
- Merged `org.mozilla.gecko.gfx.LayerSession` into [`GeckoSession`](../GeckoSession.html)
- Added [`GeckoSession.MediaDelegate`](../GeckoSession.MediaDelegate.html) and
  [`MediaElement`](../MediaElement.html). This allow monitoring and control of web
  media elements (play, pause, seek, etc).
- Removed unused `access` parameter from
  [`GeckoSession.PermissionDelegate#onContentPermissionRequest`](../GeckoSession.PermissionDelegate.html#onContentPermissionRequest-org.mozilla.geckoview.GeckoSession-java.lang.String-int-org.mozilla.geckoview.GeckoSession.PermissionDelegate.Callback-)
- Added [`WebMessage`](../WebMessage.html), [`WebRequest`](../WebRequest.html),
  [`WebResponse`](../WebResponse.html), and
  [`GeckoWebExecutor`](../GeckoWebExecutor.html). This exposes Gecko networking to
  apps. It includes speculative connections, name resolution, and a Fetch-like
  HTTP API.
- Added [`GeckoSession.HistoryDelegate`](../GeckoSession.HistoryDelegate.html).
  This allows apps to implement their own history storage system and provide
  visited link status.
- Added
  [`ContentDelegate#onFirstComposite`](../GeckoSession.ContentDelegate.html#onFirstComposite-org.mozilla.geckoview.GeckoSession-)
  to get first composite callback after a compositor start.
- Changed `LoadRequest.isUserTriggered` to
  [`isRedirect`](../GeckoSession.NavigationDelegate.LoadRequest#isRedirect)
- Added
  [`GeckoSession.LOAD_FLAGS_BYPASS_CLASSIFIER`](../GeckoSession#LOAD_FLAGS_BYPASS_CLASSIFIER)
  to bypass the URI classifier.
- Added a `protected` empty constructor to all field-only classes so that apps
  can mock these classes in tests.

[api-version]: 723adca536354bfa81afb83da5045ea6de8aa602
