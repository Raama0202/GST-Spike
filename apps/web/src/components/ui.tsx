import type * as React from 'react';
import { ReactNode } from 'react';
import clsx from 'clsx';

export function Button({ children, className, variant = 'primary', ...props }: React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'primary' | 'secondary' | 'ghost' }) {
  return (
    <button className={clsx('button group', `button-${variant}`, className)} {...props}>
      <span>{children}</span>
    </button>
  );
}

export function Panel({ children, className }: { children: ReactNode; className?: string }) {
  return <section className={clsx('panel-shell', className)}><div className="panel-core">{children}</div></section>;
}

export function Metric({ label, value, tone = 'neutral' }: { label: string; value: ReactNode; tone?: 'neutral' | 'good' | 'warn' | 'info' }) {
  return <div className={clsx('metric', `metric-${tone}`)}><span>{label}</span><strong>{value}</strong></div>;
}

export function Status({ children, tone = 'neutral' }: { children: ReactNode; tone?: 'neutral' | 'good' | 'warn' | 'bad' | 'info' }) {
  return <span className={clsx('status', `status-${tone}`)}>{children}</span>;
}

export function Field({ label, ...props }: React.InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  return <label className="field"><span>{label}</span><input {...props} /></label>;
}

export function SelectField({ label, children, ...props }: React.SelectHTMLAttributes<HTMLSelectElement> & { label: string; children: ReactNode }) {
  return <label className="field"><span>{label}</span><select {...props}>{children}</select></label>;
}

export function DataTable({ children }: { children: ReactNode }) {
  return <div className="table-wrap"><table>{children}</table></div>;
}

export function EmptyState({ title, body }: { title: string; body: string }) {
  return <div className="empty"><strong>{title}</strong><p>{body}</p></div>;
}
