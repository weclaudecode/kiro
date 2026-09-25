import type { ReactNode } from "react";

interface Props {
  title: string;
  subtitle?: string;
  actions?: ReactNode;
  span?: 4 | 6 | 8 | 12;
  children: ReactNode;
  /** Children render edge-to-edge (tables) instead of inside .card-body padding. */
  flush?: boolean;
}

export function Card({ title, subtitle, actions, span = 12, children, flush = false }: Props) {
  return (
    <article className={`card span-${span}`}>
      <header className="card-header">
        <div>
          <h2 className="card-title">{title}</h2>
          {subtitle && <p className="card-subtitle">{subtitle}</p>}
        </div>
        {actions}
      </header>
      {flush ? children : <div className="card-body">{children}</div>}
    </article>
  );
}
