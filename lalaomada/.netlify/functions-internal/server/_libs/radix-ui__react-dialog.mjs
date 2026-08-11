import { r as reactExports, j as jsxRuntimeExports } from "./react.mjs";
import { c as composeEventHandlers } from "./radix-ui__primitive.mjs";
import { u as useComposedRefs } from "./radix-ui__react-compose-refs.mjs";
import { c as createContextScope } from "./radix-ui__react-context.mjs";
import { u as useId } from "./radix-ui__react-id.mjs";
import { u as useControllableState } from "./@radix-ui/react-use-controllable-state+[...].mjs";
import { u as useDismissableLayerSurface, D as DismissableLayer } from "./@radix-ui/react-dismissable-layer+[...].mjs";
import { F as FocusScope } from "./radix-ui__react-focus-scope.mjs";
import { P as Portal } from "./radix-ui__react-portal.mjs";
import { P as Presence } from "./radix-ui__react-presence.mjs";
import { P as Primitive } from "./radix-ui__react-primitive.mjs";
import { u as useFocusGuards } from "./radix-ui__react-focus-guards.mjs";
import { u as useLayoutEffect2 } from "./@radix-ui/react-use-layout-effect+[...].mjs";
import { R as ReactRemoveScroll } from "./react-remove-scroll.mjs";
import { h as hideOthers } from "./aria-hidden.mjs";
import { c as createSlot } from "./radix-ui__react-slot.mjs";
var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
var DIALOG_NAME = "Dialog";
var [createDialogContext, createDialogScope] = createContextScope(DIALOG_NAME);
var [DialogProvider, useDialogContext] = createDialogContext(DIALOG_NAME);
var Dialog = /* @__PURE__ */ __name((props) => {
  const {
    __scopeDialog,
    children,
    open: openProp,
    defaultOpen,
    onOpenChange,
    modal = true
  } = props;
  const triggerRef = reactExports.useRef(null);
  const contentRef = reactExports.useRef(null);
  const [open, setOpen] = useControllableState({
    prop: openProp,
    defaultProp: defaultOpen ?? false,
    onChange: onOpenChange,
    caller: DIALOG_NAME
  });
  const [titleCount, setTitleCount] = reactExports.useState(0);
  const [descriptionCount, setDescriptionCount] = reactExports.useState(0);
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    DialogProvider,
    {
      scope: __scopeDialog,
      triggerRef,
      contentRef,
      contentId: useId(),
      titleId: useId(),
      descriptionId: useId(),
      titlePresent: titleCount > 0,
      descriptionPresent: descriptionCount > 0,
      setTitleCount,
      setDescriptionCount,
      open,
      onOpenChange: setOpen,
      onOpenToggle: reactExports.useCallback(() => setOpen((prevOpen) => !prevOpen), [setOpen]),
      modal,
      children
    }
  );
}, "Dialog");
var TRIGGER_NAME = "DialogTrigger";
var DialogTrigger = /* @__PURE__ */ reactExports.forwardRef(
  /* @__PURE__ */ __name(function DialogTrigger2(props, forwardedRef) {
    const { __scopeDialog, ...triggerProps } = props;
    const context = useDialogContext(TRIGGER_NAME, __scopeDialog);
    const composedTriggerRef = useComposedRefs(forwardedRef, context.triggerRef);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(
      Primitive.button,
      {
        type: "button",
        "aria-haspopup": "dialog",
        "aria-expanded": context.open,
        "aria-controls": context.open ? context.contentId : void 0,
        "data-state": getState(context.open),
        ...triggerProps,
        ref: composedTriggerRef,
        onClick: composeEventHandlers(props.onClick, context.onOpenToggle)
      }
    );
  }, "DialogTrigger")
);
var PORTAL_NAME = "DialogPortal";
var [PortalProvider, usePortalContext] = createDialogContext(PORTAL_NAME, {
  forceMount: void 0
});
var DialogPortal = /* @__PURE__ */ __name((props) => {
  const { __scopeDialog, forceMount, children, container } = props;
  const context = useDialogContext(PORTAL_NAME, __scopeDialog);
  return /* @__PURE__ */ jsxRuntimeExports.jsx(PortalProvider, { scope: __scopeDialog, forceMount, children: reactExports.Children.map(children, (child) => /* @__PURE__ */ jsxRuntimeExports.jsx(Presence, { present: forceMount || context.open, children: /* @__PURE__ */ jsxRuntimeExports.jsx(Portal, { asChild: true, container, children: child }) })) });
}, "DialogPortal");
var OVERLAY_NAME = "DialogOverlay";
var DialogOverlay = /* @__PURE__ */ reactExports.forwardRef(
  /* @__PURE__ */ __name(function DialogOverlay2(props, forwardedRef) {
    const portalContext = usePortalContext(OVERLAY_NAME, props.__scopeDialog);
    const { forceMount = portalContext.forceMount, ...overlayProps } = props;
    const context = useDialogContext(OVERLAY_NAME, props.__scopeDialog);
    return context.modal ? /* @__PURE__ */ jsxRuntimeExports.jsx(Presence, { present: forceMount || context.open, children: /* @__PURE__ */ jsxRuntimeExports.jsx(DialogOverlayImpl, { ...overlayProps, ref: forwardedRef }) }) : null;
  }, "DialogOverlay")
);
var Slot = createSlot("DialogOverlay.RemoveScroll");
var DialogOverlayImpl = /* @__PURE__ */ reactExports.forwardRef(
  // blank line to reduce diff noise
  /* @__PURE__ */ __name(function DialogOverlayImpl2(props, forwardedRef) {
    const { __scopeDialog, ...overlayProps } = props;
    const context = useDialogContext(OVERLAY_NAME, __scopeDialog);
    const registerDismissableSurface = useDismissableLayerSurface();
    const composedRefs = useComposedRefs(forwardedRef, registerDismissableSurface);
    return (
      // Make sure `Content` is scrollable even when it doesn't live inside `RemoveScroll`
      // ie. when `Overlay` and `Content` are siblings
      /* @__PURE__ */ jsxRuntimeExports.jsx(ReactRemoveScroll, { as: Slot, allowPinchZoom: true, shards: [context.contentRef], children: /* @__PURE__ */ jsxRuntimeExports.jsx(
        Primitive.div,
        {
          "data-state": getState(context.open),
          ...overlayProps,
          ref: composedRefs,
          style: { pointerEvents: "auto", ...overlayProps.style }
        }
      ) })
    );
  }, "DialogOverlayImpl")
);
var CONTENT_NAME = "DialogContent";
var DialogContent = /* @__PURE__ */ reactExports.forwardRef(
  /* @__PURE__ */ __name(function DialogContent2(props, forwardedRef) {
    const portalContext = usePortalContext(CONTENT_NAME, props.__scopeDialog);
    const { forceMount = portalContext.forceMount, ...contentProps } = props;
    const context = useDialogContext(CONTENT_NAME, props.__scopeDialog);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(Presence, { present: forceMount || context.open, children: context.modal ? /* @__PURE__ */ jsxRuntimeExports.jsx(DialogContentModal, { ...contentProps, ref: forwardedRef }) : /* @__PURE__ */ jsxRuntimeExports.jsx(DialogContentNonModal, { ...contentProps, ref: forwardedRef }) });
  }, "DialogContent")
);
var DialogContentModal = /* @__PURE__ */ reactExports.forwardRef(
  // blank line to reduce diff noise
  /* @__PURE__ */ __name(function DialogContentModal2(props, forwardedRef) {
    const context = useDialogContext(CONTENT_NAME, props.__scopeDialog);
    const contentRef = reactExports.useRef(null);
    const composedRefs = useComposedRefs(forwardedRef, context.contentRef, contentRef);
    reactExports.useEffect(() => {
      const content = contentRef.current;
      if (content) return hideOthers(content);
    }, []);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(
      DialogContentImpl,
      {
        ...props,
        ref: composedRefs,
        trapFocus: context.open,
        disableOutsidePointerEvents: context.open,
        onCloseAutoFocus: composeEventHandlers(props.onCloseAutoFocus, (event) => {
          event.preventDefault();
          context.triggerRef.current?.focus();
        }),
        onPointerDownOutside: composeEventHandlers(props.onPointerDownOutside, (event) => {
          const originalEvent = event.detail.originalEvent;
          const ctrlLeftClick = originalEvent.button === 0 && originalEvent.ctrlKey === true;
          const isRightClick = originalEvent.button === 2 || ctrlLeftClick;
          if (isRightClick) event.preventDefault();
        }),
        onFocusOutside: composeEventHandlers(
          props.onFocusOutside,
          (event) => event.preventDefault()
        )
      }
    );
  }, "DialogContentModal")
);
var DialogContentNonModal = /* @__PURE__ */ reactExports.forwardRef(
  // blank line to reduce diff noise
  /* @__PURE__ */ __name(function DialogContentNonModal2(props, forwardedRef) {
    const context = useDialogContext(CONTENT_NAME, props.__scopeDialog);
    const hasInteractedOutsideRef = reactExports.useRef(false);
    const hasPointerDownOutsideRef = reactExports.useRef(false);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(
      DialogContentImpl,
      {
        ...props,
        ref: forwardedRef,
        trapFocus: false,
        disableOutsidePointerEvents: false,
        onCloseAutoFocus: (event) => {
          props.onCloseAutoFocus?.(event);
          if (!event.defaultPrevented) {
            if (!hasInteractedOutsideRef.current) context.triggerRef.current?.focus();
            event.preventDefault();
          }
          hasInteractedOutsideRef.current = false;
          hasPointerDownOutsideRef.current = false;
        },
        onInteractOutside: (event) => {
          props.onInteractOutside?.(event);
          if (!event.defaultPrevented) {
            hasInteractedOutsideRef.current = true;
            if (event.detail.originalEvent.type === "pointerdown") {
              hasPointerDownOutsideRef.current = true;
            }
          }
          const target = event.target;
          const targetIsTrigger = context.triggerRef.current?.contains(target);
          if (targetIsTrigger) event.preventDefault();
          if (event.detail.originalEvent.type === "focusin" && hasPointerDownOutsideRef.current) {
            event.preventDefault();
          }
        }
      }
    );
  }, "DialogContentNonModal")
);
var DialogContentImpl = /* @__PURE__ */ reactExports.forwardRef(
  // blank line to reduce diff noise
  /* @__PURE__ */ __name(function DialogContentImpl2(props, forwardedRef) {
    const { __scopeDialog, trapFocus, onOpenAutoFocus, onCloseAutoFocus, ...contentProps } = props;
    const context = useDialogContext(CONTENT_NAME, __scopeDialog);
    useFocusGuards();
    return /* @__PURE__ */ jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, { children: /* @__PURE__ */ jsxRuntimeExports.jsx(
      FocusScope,
      {
        asChild: true,
        loop: true,
        trapped: trapFocus,
        onMountAutoFocus: onOpenAutoFocus,
        onUnmountAutoFocus: onCloseAutoFocus,
        children: /* @__PURE__ */ jsxRuntimeExports.jsx(
          DismissableLayer,
          {
            role: "dialog",
            id: context.contentId,
            "aria-describedby": context.descriptionPresent ? context.descriptionId : void 0,
            "aria-labelledby": context.titlePresent ? context.titleId : void 0,
            "data-state": getState(context.open),
            ...contentProps,
            ref: forwardedRef,
            deferPointerDownOutside: true,
            onDismiss: () => context.onOpenChange(false)
          }
        )
      }
    ) });
  }, "DialogContentImpl")
);
var TITLE_NAME = "DialogTitle";
var DialogTitle = /* @__PURE__ */ reactExports.forwardRef(
  /* @__PURE__ */ __name(function DialogTitle2(props, forwardedRef) {
    const { __scopeDialog, ...titleProps } = props;
    const context = useDialogContext(TITLE_NAME, __scopeDialog);
    const { setTitleCount } = context;
    useLayoutEffect2(() => {
      setTitleCount((count) => count + 1);
      return () => setTitleCount((count) => count - 1);
    }, [setTitleCount]);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(Primitive.h2, { id: context.titleId, ...titleProps, ref: forwardedRef });
  }, "DialogTitle")
);
var DESCRIPTION_NAME = "DialogDescription";
var DialogDescription = /* @__PURE__ */ reactExports.forwardRef(
  // blank line to reduce diff noise
  /* @__PURE__ */ __name(function DialogDescription2(props, forwardedRef) {
    const { __scopeDialog, ...descriptionProps } = props;
    const context = useDialogContext(DESCRIPTION_NAME, __scopeDialog);
    const { setDescriptionCount } = context;
    useLayoutEffect2(() => {
      setDescriptionCount((count) => count + 1);
      return () => setDescriptionCount((count) => count - 1);
    }, [setDescriptionCount]);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(Primitive.p, { id: context.descriptionId, ...descriptionProps, ref: forwardedRef });
  }, "DialogDescription")
);
var CLOSE_NAME = "DialogClose";
var DialogClose = /* @__PURE__ */ reactExports.forwardRef(
  /* @__PURE__ */ __name(function DialogClose2(props, forwardedRef) {
    const { __scopeDialog, ...closeProps } = props;
    const context = useDialogContext(CLOSE_NAME, __scopeDialog);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(
      Primitive.button,
      {
        type: "button",
        ...closeProps,
        ref: forwardedRef,
        onClick: composeEventHandlers(props.onClick, () => context.onOpenChange(false))
      }
    );
  }, "DialogClose")
);
function getState(open) {
  return open ? "open" : "closed";
}
__name(getState, "getState");
export {
  DialogPortal as D,
  DialogContent as a,
  DialogTitle as b,
  DialogDescription as c,
  DialogClose as d,
  createDialogScope as e,
  DialogOverlay as f,
  Dialog as g,
  DialogTrigger as h
};
