# Split child modules in passive and active.

## Background

GeckoView has a module infrastructure. Each `Delegate` on the GeckoView API
corresponds to a two chrome javascript modules
- the parent module loaded in the main process and
- the child module loaded as a frame script on the content process.

E.g. for the `Navigation` feature, we have this group of modules:

- `GeckoSession.NavigationDelegate`, GV API that consumers use to register the
  delegate
- `GeckoViewNavigation.jsm`, chrome module that is loaded in the main process
- `GeckoViewNavigationChild.js`, chrome module that is loaded in the content
  process as a frame script

The parent and child modules have three possible states:

- `initial`, right after the javascript module is loaded in the process
- `enabled`, whenever the GV consumer has registered the corresponding `Delegate`
- `disabled`, whenever there is no corresponding `Delegate` registered.

Whenever the child module is being loaded, the parent module halts all IPC
messages and wait until the child module sends an IPC message signaling that it
has started up. After that, the parent process releases all IPC messages that
were previously held up.

Whenever the consumer registers a `Delegate` using the GV API the java main
thread sends a message to the Gecko main thread to enable the module. This
triggers an IPC message between the main process and the content process to
enable the child module. 

This infrastructure clashes with some Gecko infrastructure which has a similar
(but not quite the same) way of dealing with coordinating IPC messages and
scripts.

Let's look at a concrete example (which motivates this change).

The Gecko counter part for `GeckoViewNavigation` is `LoadURIDelegate`.
`LoadURIDelegate` is attached to the `docShell` by setting
`docShell.loadURIDelegate`. To make a `browser` navigate to a page, GeckoView uses
`browser.loadURI` on the parent process. The browser custom element then uses a
remote `WebNavigation` object to send the message over the child process and
start the navigation. This machinery works fine when all modules are loaded and
in their correct enabled state, however, when a load happens while GeckoView is
starting up, we have cases where the parent module is enabled and the child is
not, so we end up missing some `LoadURIDelegate` messages (e.g. sometimes the
consumer will not receive a `LoadRequest` or a `LoadError`).

Side note: These cases are actually more common that might initially seem:
Android often kills mercifully our processes, so often when a user loads a
page, the load will race with Gecko and GeckoView startup.

Let's look at a problematic timeline (arrows `\__>` indicate IPCs).

```
  Main Process                           Content Process
  (1) Load GeckoViewNavigation
          \____________________________> (1C) Load GeckoViewNavigationChild (disabled)
  (2) Pause GeckoView messages
  (3) Set GeckoViewNavigation enabled
                                         (2C) Send ContentModuleLoaded message
  (4) onContentModuleLoaded  <________________________/
       |
       +-- (4.1) Unpause messaging
       |         Call browser.loadURI
       |               \______________>  (3C) browser initiates navigation
       |                                 (4C) LoadURIDelegate.loadUri call ignored because
       |                                      module is disabled
       +-- (4.2) Set child module enabled
                        \_____________>  (5C) Set GeckoViewNavigationChild enabled,
                                              LoadURIDelegate calls now start working
```

As you can see in the above timeline, when the `loadURI` call in (4.1) reaches
the content process before the child module is enabled in (5C), the `LoadURI`
delegate messages are ignored, which causes GeckoView to ignore some load
requests or load error messages. Note that sometimes the order is the
following:

```
                                               .......
  (4) Unpause messaging  <________________________/
       |
       +-- (4.1) Call browser.loadURI
       |             \________________>  (3C) browser initiates navigation
       |
       +-- (4.2) Set child module enabled
                        \_____________>  (5C) Set GeckoViewNavigationChild enabled,
                                              LoadURIDelegate calls now start working
                                         (4C) LoadURIDelegate.loadUri call correctly
                                              handled
```

And the code works correctly.

## Possible solution

### Naive solution

The simplest solution would be to hold off any `loadURI` calls in the main
process until the child module reports that it has enabled itself. This has (at
least) two problems:

- We introduce for an additional IPC round trip in the critical startup path
  that is not needed, in theory we should be able to tell the content process
to load a page as soon as it has finished started up, without waiting for the
main process acknowledgment.
- We don't fix the larger class of problems, we just fix this one off. Every
  other object that is split between parent and child modules will cause
similar timing bugs.


### Proposed solution

To avoid the additional IPC round trip, and solve this problem in a generic
way, we split modules in two parts:

- _passive_ modules that are loaded immediately and never disabled (always
  active). These modules will replace whatever logic today runs in the `onInit`
block.
- _active_ modules that are loaded only when the module is enabled. These
  modules will replace the logic that runs in the `onEnable` block. The module is
loaded only when it's active, so to avoid any enable IPC message, and it
incidentally removes the need to clean up when the module is disabled, as we
just unload it instead. This is potentially a little slower than just sending a
disable message, but we don't expect consumers to enable and disable modules
frequently so we choose to optimize for the common case of consumers enabling
modules just once (at startup).

With this change, we can load both active and passive modules concurrently,
avoiding waiting for the module to be loaded before enabling, effectively
guaranteeing that when the parent module uses any Gecko object the child module
is already enabled and ready to receive messages.

This is the revised timeline:

```
  Main Process                           Content Process
  (1) Load GeckoViewNavigation
          |
          +--------------------------->  (1C) Load GeckoViewNavigationChild passive
          | 
          +--(if module is enabled)--->  (2C) Load GeckoViewNavigationChild active
                                         (3C) LoadURIDelegate starts working

  (2) Pause GeckoView messages
  (3) Set GeckoViewNavigation enabled
                                         (4C) Send ContentModuleLoaded message passive
                                    +--------------------+
                                   /     (5C) Send ContentModuleLoaded message active
  (4) onContentModuleLoaded <---+------------------------+
       |
       + Unpause messaging
       |
       + Call browser.loadURI
                     \________________>  (6C) browser initiates navigation
                                         (7C) LoadURIDelegate.loadUri call correctly
                                               handled
```

As you can see from the timeline, the `LoadURIDelegate` will always be enabled
before the parent module starts sending messages to it, and so will any object
on the Gecko side, since we wait until both the passive and active modules have
loaded.

## Performance considerations

Performance might be inpacted by two things: increasing the number of frame
scripts that we have to load and the fact that we now wait for two scripts to
load before re-enabling messaging (and thus blocking first page loads).
Assuming that loading frame scripts is run in parallel, this should actually
sligthly increase performance as now we can load more code at once.
Experimental data doesn't show any regression (see try) so it seems reasonable
to assume that this change would not impact performance in a meaningful way.

## e10s multi

This change should continue to work as intended in a e10s world. The only
difference here is that we receive content module messages from one of many
content processes, but otherwise everything should continue to work as in the
single content process case.

## Fission

In the Fission world, Actors replace frameScripts and are very similar to
modules in GeckoView. In that world we will probably replace the entire module
structure with two Actors, one actor will handle the passive part of the module
(both on the parent side and the child side) and one will handle the active
part, actors should support the dynamic loading of the active module out of the
box.

Potentially, we could split the parent process modules too with this change, so
that we don't have to do it as part of Fission. However, since this change is
very pervasive enough, I would opt to not do that right now and try to land
this first.

## Try

First implementation can be found in this try run:
https://hg.mozilla.org/try/rev/8ac21ec4ce8a7ca8bef41a7144cf6a747d1028b0.
Performance test is here:
https://treeherder.mozilla.org/#/jobs?repo=try&revision=c174f20c87bf8d46f0dd84b933d1edbcb7789d4d&searchStr=raptor
