# GST SaaS Suite Design System

## Design Tokens

The interface uses a restrained product palette with deep graphite shells, porcelain work surfaces, emerald success accents, amber operational warnings, and blue information states. CSS tokens live in `apps/web/src/styles.css` and are expressed with OKLCH values.

## Typography

The UI uses `Geist` with a system fallback. Product labels, data, and controls use a compact fixed scale. Headings are confident but never hero-sized inside dashboard surfaces.

## Components

Core reusable components live in `apps/web/src/components/ui.tsx`: shell, product cards, metric tiles, buttons, status pills, command inputs, panels, progress bars, tables, and form fields.

## Motion

Transitions use transform and opacity with custom cubic-bezier curves. Product switching has a short premium reveal, cards lift subtly on hover, and reduced motion disables transform-heavy effects.

## Layout

The suite uses a connected app shell with a floating product switcher, contextual side navigation, dense dashboard grids, and responsive single-column collapse below tablet widths.
