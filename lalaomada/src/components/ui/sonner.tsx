import { Toaster as Sonner } from "sonner";

type ToasterProps = React.ComponentProps<typeof Sonner>;

const Toaster = ({ ...props }: ToasterProps) => {
  return (
    <Sonner
      className="toaster group"
      position="top-center"
      // Keep toasts subtle and uniform — no richColors, short duration, compact
      duration={2500}
      toastOptions={{
        unstyled: false,
        style: {
          padding: "6px 14px",
          borderRadius: "9999px",
          fontSize: "12px",
          fontWeight: 500,
          minHeight: "auto",
          maxWidth: "90vw",
        },
        classNames: {
          toast:
            "group toast group-[.toaster]:bg-card group-[.toaster]:text-foreground group-[.toaster]:border group-[.toaster]:border-border group-[.toaster]:shadow-sm group-[.toaster]:px-3 group-[.toaster]:py-1.5 group-[.toaster]:text-xs group-[.toaster]:font-medium group-[.toaster]:rounded-full",
          description: "group-[.toast]:text-muted-foreground group-[.toast]:text-xs",
          actionButton: "group-[.toast]:bg-primary group-[.toast]:text-primary-foreground group-[.toast]:rounded-full group-[.toast]:text-xs group-[.toast]:px-2 group-[.toast]:py-0.5",
          cancelButton: "group-[.toast]:bg-muted group-[.toast]:text-muted-foreground group-[.toast]:rounded-full group-[.toast]:text-xs",
          // Uniform styles for all types — no loud colors
          success: "group-[.toaster]:bg-card group-[.toaster]:text-foreground",
          error: "group-[.toaster]:bg-card group-[.toaster]:text-foreground group-[.toaster]:border-destructive/30",
          warning: "group-[.toaster]:bg-card group-[.toaster]:text-foreground group-[.toaster]:border-amber-500/30",
          info: "group-[.toaster]:bg-card group-[.toaster]:text-foreground",
        },
      }}
      {...props}
    />
  );
};

export { Toaster };
