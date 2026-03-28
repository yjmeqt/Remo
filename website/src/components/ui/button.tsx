import * as React from "react";
import { cn } from "@/lib/utils";

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "default" | "outline" | "ghost";
  size?: "default" | "sm" | "lg";
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = "default", size = "default", ...props }, ref) => {
    return (
      <button
        ref={ref}
        className={cn(
          "inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-zinc-300 disabled:pointer-events-none disabled:opacity-50",
          variant === "default" &&
            "bg-zinc-50 text-zinc-900 shadow hover:bg-zinc-200",
          variant === "outline" &&
            "border border-zinc-800 bg-transparent text-zinc-300 hover:bg-zinc-800 hover:text-zinc-50",
          variant === "ghost" &&
            "text-zinc-400 hover:bg-zinc-800 hover:text-zinc-50",
          size === "default" && "h-9 px-4 py-2",
          size === "sm" && "h-8 rounded-md px-3 text-xs",
          size === "lg" && "h-10 rounded-md px-8",
          className
        )}
        {...props}
      />
    );
  }
);
Button.displayName = "Button";

export { Button };
