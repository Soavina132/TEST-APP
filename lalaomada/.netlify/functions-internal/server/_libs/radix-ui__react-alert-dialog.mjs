import { j as jsxRuntimeExports, r as reactExports } from "./react.mjs";
import { c as createContextScope } from "./radix-ui__react-context.mjs";
import { u as useComposedRefs } from "./radix-ui__react-compose-refs.mjs";
import { D as DialogPortal, a as DialogContent, b as DialogTitle, c as DialogDescription, d as DialogClose, e as createDialogScope, f as DialogOverlay, g as Dialog, h as DialogTrigger } from "./radix-ui__react-dialog.mjs";
import { c as composeEventHandlers } from "./radix-ui__primitive.mjs";
var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
var ROOT_NAME = "AlertDialog";
var [createAlertDialogContext, createAlertDialogScope] = createContextScope(ROOT_NAME, [
  createDialogScope
]);
var useDialogScope = createDialogScope();
var AlertDialog = /* @__PURE__ */ __name((props) => {
  const { __scopeAlertDialog, ...alertDialogProps } = props;
  const dialogScope = useDialogScope(__scopeAlertDialog);
  return /* @__PURE__ */ jsxRuntimeExports.jsx(Dialog, { ...dialogScope, ...alertDialogProps, modal: true });
}, "AlertDialog");
reactExports.forwardRef(
  /* @__PURE__ */ __name(function AlertDialogTrigger2(props, forwardedRef) {
    const { __scopeAlertDialog, ...triggerProps } = props;
    const dialogScope = useDialogScope(__scopeAlertDialog);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(DialogTrigger, { ...dialogScope, ...triggerProps, ref: forwardedRef });
  }, "AlertDialogTrigger")
);
var AlertDialogPortal = /* @__PURE__ */ __name((props) => {
  const { __scopeAlertDialog, ...portalProps } = props;
  const dialogScope = useDialogScope(__scopeAlertDialog);
  return /* @__PURE__ */ jsxRuntimeExports.jsx(DialogPortal, { ...dialogScope, ...portalProps });
}, "AlertDialogPortal");
var AlertDialogOverlay = reactExports.forwardRef(
  /* @__PURE__ */ __name(function AlertDialogOverlay2(props, forwardedRef) {
    const { __scopeAlertDialog, ...overlayProps } = props;
    const dialogScope = useDialogScope(__scopeAlertDialog);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(DialogOverlay, { ...dialogScope, ...overlayProps, ref: forwardedRef });
  }, "AlertDialogOverlay")
);
var CONTENT_NAME = "AlertDialogContent";
var [AlertDialogContentProvider, useAlertDialogContentContext] = createAlertDialogContext(CONTENT_NAME);
var AlertDialogContent = reactExports.forwardRef(
  /* @__PURE__ */ __name(function AlertDialogContent2(props, forwardedRef) {
    const { __scopeAlertDialog, children, ...contentProps } = props;
    const dialogScope = useDialogScope(__scopeAlertDialog);
    const contentRef = reactExports.useRef(null);
    const composedRefs = useComposedRefs(forwardedRef, contentRef);
    const cancelRef = reactExports.useRef(null);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(AlertDialogContentProvider, { scope: __scopeAlertDialog, cancelRef, children: /* @__PURE__ */ jsxRuntimeExports.jsx(
      DialogContent,
      {
        role: "alertdialog",
        ...dialogScope,
        ...contentProps,
        ref: composedRefs,
        onOpenAutoFocus: composeEventHandlers(contentProps.onOpenAutoFocus, (event) => {
          event.preventDefault();
          cancelRef.current?.focus({ preventScroll: true });
        }),
        onPointerDownOutside: (event) => event.preventDefault(),
        onInteractOutside: (event) => event.preventDefault(),
        children
      }
    ) });
  }, "AlertDialogContent")
);
var AlertDialogTitle = reactExports.forwardRef(
  /* @__PURE__ */ __name(function AlertDialogTitle2(props, forwardedRef) {
    const { __scopeAlertDialog, ...titleProps } = props;
    const dialogScope = useDialogScope(__scopeAlertDialog);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(DialogTitle, { ...dialogScope, ...titleProps, ref: forwardedRef });
  }, "AlertDialogTitle")
);
var AlertDialogDescription = reactExports.forwardRef(/* @__PURE__ */ __name(function AlertDialogDescription2(props, forwardedRef) {
  const { __scopeAlertDialog, ...descriptionProps } = props;
  const dialogScope = useDialogScope(__scopeAlertDialog);
  return /* @__PURE__ */ jsxRuntimeExports.jsx(DialogDescription, { ...dialogScope, ...descriptionProps, ref: forwardedRef });
}, "AlertDialogDescription"));
var AlertDialogAction = reactExports.forwardRef(
  /* @__PURE__ */ __name(function AlertDialogAction2(props, forwardedRef) {
    const { __scopeAlertDialog, ...actionProps } = props;
    const dialogScope = useDialogScope(__scopeAlertDialog);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(DialogClose, { ...dialogScope, ...actionProps, ref: forwardedRef });
  }, "AlertDialogAction")
);
var CANCEL_NAME = "AlertDialogCancel";
var AlertDialogCancel = reactExports.forwardRef(
  /* @__PURE__ */ __name(function AlertDialogCancel2(props, forwardedRef) {
    const { __scopeAlertDialog, ...cancelProps } = props;
    const { cancelRef } = useAlertDialogContentContext(CANCEL_NAME, __scopeAlertDialog);
    const dialogScope = useDialogScope(__scopeAlertDialog);
    const ref = useComposedRefs(forwardedRef, cancelRef);
    return /* @__PURE__ */ jsxRuntimeExports.jsx(DialogClose, { ...dialogScope, ...cancelProps, ref });
  }, "AlertDialogCancel")
);
var Root2 = AlertDialog;
var Portal2 = AlertDialogPortal;
var Overlay2 = AlertDialogOverlay;
var Content2 = AlertDialogContent;
var Action = AlertDialogAction;
var Cancel = AlertDialogCancel;
var Title2 = AlertDialogTitle;
var Description2 = AlertDialogDescription;
export {
  Action as A,
  Content2 as C,
  Description2 as D,
  Overlay2 as O,
  Portal2 as P,
  Root2 as R,
  Title2 as T,
  Cancel as a
};
