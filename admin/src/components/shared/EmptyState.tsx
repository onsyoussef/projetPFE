import type { ReactNode } from 'react';
import { UserX } from 'lucide-react';

interface EmptyStateProps {
  title?: string;
  description?: string;
  icon?: ReactNode;
}

export default function EmptyState({
  title = 'Aucun résultat',
  description = 'Aucun médecin ne correspond à vos critères de recherche.',
  icon,
}: EmptyStateProps) {
  return (
    <div className="dashboard-empty">
      <div className="dashboard-empty-icon">
        {icon ?? <UserX size={28} className="text-text-secondary" />}
      </div>
      <h3 className="dashboard-empty-title">{title}</h3>
      <p className="dashboard-empty-desc">{description}</p>
    </div>
  );
}
