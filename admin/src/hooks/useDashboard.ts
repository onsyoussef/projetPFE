import { useQuery } from '@tanstack/react-query';
import { getDashboardStats } from '@/api/doctors';
import { DASHBOARD_QUERY_KEY } from '@/hooks/useDoctors';

export function useDashboard() {
  return useQuery({
    queryKey: [DASHBOARD_QUERY_KEY],
    queryFn: getDashboardStats,
    refetchInterval: 30_000,
  });
}
