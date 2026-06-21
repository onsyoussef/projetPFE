import { Skeleton } from 'antd';

interface LoadingSkeletonProps {
  rows?: number;
  type?: 'table' | 'cards' | 'page';
}

export default function LoadingSkeleton({ rows = 5, type = 'page' }: LoadingSkeletonProps) {
  if (type === 'cards') {
    return (
      <div className="kpi-grid">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="rounded-xl bg-white p-5 shadow-card">
            <Skeleton active paragraph={{ rows: 2 }} />
          </div>
        ))}
      </div>
    );
  }

  if (type === 'table') {
    return (
      <div className="rounded-xl bg-surface p-4 shadow-card">
        <Skeleton active paragraph={{ rows }} />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <Skeleton active paragraph={{ rows: 1 }} />
      <LoadingSkeleton type="cards" />
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <Skeleton active paragraph={{ rows: 6 }} />
        <Skeleton active paragraph={{ rows: 6 }} />
      </div>
    </div>
  );
}
