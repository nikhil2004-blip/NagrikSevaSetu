import { cva } from "class-variance-authority";
import { twMerge } from "tailwind-merge";

/** Utilities */
// eslint-disable-next-line react-refresh/only-export-components
export function cn(...inputs) {
  return twMerge(inputs);
}

/** Card */
export function Card({ className, children, ...props }) {
  return (
    <div className={cn("bg-surface-container-lowest border border-outline-variant rounded shadow-sm flex flex-col", className)} {...props}>
      {children}
    </div>
  );
}

export function CardHeader({ className, children, ...props }) {
  return (
    <div className={cn("bg-surface-container px-6 py-2 border-b border-outline-variant", className)} {...props}>
      {children}
    </div>
  );
}

export function CardTitle({ className, children, ...props }) {
  return (
    <h3 className={cn("font-headline-sm text-headline-sm text-primary", className)} {...props}>
      {children}
    </h3>
  );
}

export function CardContent({ className, children, ...props }) {
  return (
    <div className={cn("p-6 flex-1", className)} {...props}>
      {children}
    </div>
  );
}

/** Button */
const buttonVariants = cva(
  "inline-flex items-center justify-center rounded transition-colors focus-visible-ring disabled:opacity-50 disabled:cursor-not-allowed font-label-md text-label-md",
  {
    variants: {
      variant: {
        default: "bg-primary text-on-primary hover:bg-primary-container",
        secondary: "bg-secondary-container text-on-secondary-container hover:bg-outline-variant",
        outline: "border-2 border-primary text-primary hover:bg-surface-container-low",
        ghost: "hover:bg-surface-container text-on-surface-variant",
      },
      size: {
        default: "h-12 px-6 py-2 min-w-[120px]",
        sm: "h-9 px-4 py-1",
        icon: "h-10 w-10 p-2 rounded-full",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
);

export function Button({ className, variant, size, ...props }) {
  return (
    <button className={cn(buttonVariants({ variant, size, className }))} {...props} />
  );
}

/** Badge */
const badgeVariants = cva(
  "inline-flex items-center gap-1.5 rounded-full px-4 py-1 font-label-sm text-label-sm",
  {
    variants: {
      variant: {
        default: "bg-surface-container text-on-surface",
        approved: "bg-[#e6f4ea] text-[#137333]", // Success
        pending: "bg-[#fef7e0] text-[#b06000]", // Warning
        urgent: "bg-error-container text-on-error-container", // Danger
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
);

export function Badge({ className, variant, children, ...props }) {
  return (
    <span className={cn(badgeVariants({ variant, className }))} {...props}>
      {children}
    </span>
  );
}

/** Input */
export function Input({ className, ...props }) {
  return (
    <input
      className={cn(
        "h-12 w-full border-2 border-outline rounded px-4 bg-surface focus:border-primary focus:ring-0 transition-all font-body-md text-body-md placeholder:text-outline",
        className
      )}
      {...props}
    />
  );
}

/** Label */
export function Label({ className, children, htmlFor, ...props }) {
  return (
    <label
      htmlFor={htmlFor}
      className={cn("font-label-md text-label-md text-on-surface", className)}
      {...props}
    >
      {children}
    </label>
  );
}

/** Table */
export function Table({ className, children, ...props }) {
  return (
    <div className="w-full overflow-x-auto border border-outline-variant rounded shadow-sm bg-surface-container-lowest">
      <table className={cn("w-full text-left border-collapse", className)} {...props}>
        {children}
      </table>
    </div>
  );
}

export function THead({ className, children, ...props }) {
  return (
    <thead className={cn("bg-surface-container border-b border-outline-variant", className)} {...props}>
      {children}
    </thead>
  );
}

export function TBody({ className, children, ...props }) {
  return (
    <tbody className={cn("divide-y divide-outline-variant", className)} {...props}>
      {children}
    </tbody>
  );
}

export function TR({ className, children, ...props }) {
  return (
    <tr className={cn("hover:bg-surface-container-low transition-colors group", className)} {...props}>
      {children}
    </tr>
  );
}

export function TH({ className, children, ...props }) {
  return (
    <th className={cn("px-6 py-4 font-label-md text-label-md text-on-surface-variant uppercase tracking-wider", className)} {...props}>
      {children}
    </th>
  );
}

export function TD({ className, children, ...props }) {
  return (
    <td className={cn("px-6 py-6 font-body-sm text-body-sm", className)} {...props}>
      {children}
    </td>
  );
}

/** Modal */
export function Modal({ open, onClose, title, children, actions }) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center px-4">
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" onClick={onClose} />
      <Card className="relative w-full max-w-lg shadow-xl z-10 max-h-[90vh] overflow-y-auto">
        {title && (
          <CardHeader>
            <CardTitle>{title}</CardTitle>
          </CardHeader>
        )}
        <CardContent className="mt-4">
          <div className="space-y-4">{children}</div>
        </CardContent>
        {actions && (
          <div className="border-t border-outline-variant bg-surface-container-lowest p-6 rounded-b flex justify-end gap-4">
            {actions}
          </div>
        )}
      </Card>
    </div>
  );
}
