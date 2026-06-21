import { Tag } from 'antd';
import type { DoctorStatus } from '@/types/doctor';

const config: Record<
  DoctorStatus,
  { label: string; color: string; bg: string }
> = {
  pending: { label: 'En attente', color: '#E67E22', bg: '#FEF3E2' },
  approved: { label: 'Approuvé', color: '#2ECC9A', bg: '#E8F8F0' },
  rejected: { label: 'Refusé', color: '#E74C3C', bg: '#FDEDEC' },
};

interface StatusBadgeProps {
  status: DoctorStatus;
}

export default function StatusBadge({ status }: StatusBadgeProps) {
  const { label, color, bg } = config[status] ?? config.pending;
  return (
    <Tag
      style={{
        color,
        backgroundColor: bg,
        border: 'none',
        borderRadius: 6,
        fontWeight: 500,
        padding: '2px 10px',
      }}
    >
      {label}
    </Tag>
  );
}
