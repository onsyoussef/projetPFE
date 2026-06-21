import type { ReactNode, CSSProperties } from 'react';

interface KpiCardProps {
  title: string;
  value: number;
  subtitle?: string;
  icon: ReactNode;
  color: string;
  bgColor: string;
  accentColor?: string;
  onClick?: () => void;
}

export default function KpiCard({
  title,
  value,
  subtitle,
  icon,
  color,
  bgColor,
  accentColor,
  onClick,
}: KpiCardProps) {
  const borderAccent = accentColor ?? color;

  return (
    <button
      type="button"
      onClick={onClick}
      className="kpi-card group w-full text-left"
      style={{ '--kpi-accent': borderAccent } as CSSProperties}
      disabled={!onClick}
    >
      <div className="kpi-card-inner">
        <div
          className="kpi-card-icon"
          style={{ backgroundColor: bgColor, color }}
        >
          {icon}
        </div>

        <div className="kpi-card-body">
          <span className="kpi-card-label">{title}</span>
          <span className="kpi-card-value">{value}</span>
          {subtitle && <span className="kpi-card-subtitle">{subtitle}</span>}
        </div>
      </div>
    </button>
  );
}
