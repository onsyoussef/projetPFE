import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notification } from 'antd';
import {
  getDoctors,
  getDoctorById,
  approveDoctor,
  rejectDoctor,
} from '@/api/doctors';
import type { DoctorStatus, DoctorsListParams } from '@/types/doctor';

export const DOCTORS_QUERY_KEY = 'doctors';
export const DOCTOR_QUERY_KEY = 'doctor';
export const DASHBOARD_QUERY_KEY = 'dashboard';

export function useDoctorsList(params: DoctorsListParams) {
  return useQuery({
    queryKey: [DOCTORS_QUERY_KEY, params],
    queryFn: () => getDoctors(params),
    refetchInterval: params.status === 'pending' || params.status === 'all' ? 30_000 : false,
  });
}

export function useDoctorDetail(id: string | null) {
  return useQuery({
    queryKey: [DOCTOR_QUERY_KEY, id],
    queryFn: () => getDoctorById(id!),
    enabled: !!id,
  });
}

export function useApproveDoctor() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => approveDoctor(id),
    onMutate: async (id) => {
      await queryClient.cancelQueries({ queryKey: [DOCTORS_QUERY_KEY] });
      await queryClient.cancelQueries({ queryKey: [DASHBOARD_QUERY_KEY] });

      const previousLists = queryClient.getQueriesData({ queryKey: [DOCTORS_QUERY_KEY] });

      queryClient.setQueriesData<{ doctors: { id: string; status: DoctorStatus }[]; total: number }>(
        { queryKey: [DOCTORS_QUERY_KEY] },
        (old) => {
          if (!old) return old;
          return {
            ...old,
            doctors: old.doctors.map((d) =>
              d.id === id ? { ...d, status: 'approved' as DoctorStatus } : d,
            ),
          };
        },
      );

      return { previousLists };
    },
    onSuccess: (data) => {
      const emailOk = data.notification?.emailSent;
      notification.success({
        message: 'Médecin approuvé',
        description: emailOk
          ? `${data.message} E-mail envoyé au médecin.`
          : data.message,
        placement: 'topRight',
      });
      if (data.notification && !data.notification.emailSent) {
        notification.warning({
          message: 'E-mail non envoyé',
          description:
            data.notification.errors?.join(' · ') ||
            'Vérifiez SMTP_USER et SMTP_PASS dans backend/.env',
          placement: 'topRight',
        });
      }
    },
    onError: (_err, _id, context) => {
      context?.previousLists?.forEach(([key, data]) => {
        queryClient.setQueryData(key, data);
      });
      notification.error({
        message: 'Erreur',
        description: "Impossible d'approuver ce médecin.",
        placement: 'topRight',
      });
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: [DOCTORS_QUERY_KEY] });
      queryClient.invalidateQueries({ queryKey: [DASHBOARD_QUERY_KEY] });
      queryClient.invalidateQueries({ queryKey: [DOCTOR_QUERY_KEY] });
    },
  });
}

export function useRejectDoctor() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      rejectDoctor(id, reason),
    onMutate: async ({ id }) => {
      await queryClient.cancelQueries({ queryKey: [DOCTORS_QUERY_KEY] });

      const previousLists = queryClient.getQueriesData({ queryKey: [DOCTORS_QUERY_KEY] });

      queryClient.setQueriesData<{ doctors: { id: string; status: DoctorStatus }[] }>(
        { queryKey: [DOCTORS_QUERY_KEY] },
        (old) => {
          if (!old) return old;
          return {
            ...old,
            doctors: old.doctors.map((d) =>
              d.id === id ? { ...d, status: 'rejected' as DoctorStatus } : d,
            ),
          };
        },
      );

      return { previousLists };
    },
    onSuccess: (data) => {
      const emailOk = data.notification?.emailSent;
      notification.success({
        message: 'Médecin refusé',
        description: emailOk
          ? `${data.message} E-mail envoyé au médecin.`
          : data.message,
        placement: 'topRight',
      });
      if (data.notification && !data.notification.emailSent) {
        notification.warning({
          message: 'E-mail non envoyé',
          description:
            data.notification.errors?.join(' · ') ||
            'Vérifiez SMTP_USER et SMTP_PASS dans backend/.env',
          placement: 'topRight',
        });
      }
    },
    onError: (_err, _vars, context) => {
      context?.previousLists?.forEach(([key, data]) => {
        queryClient.setQueryData(key, data);
      });
      notification.error({
        message: 'Erreur',
        description: 'Impossible de refuser ce médecin.',
        placement: 'topRight',
      });
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: [DOCTORS_QUERY_KEY] });
      queryClient.invalidateQueries({ queryKey: [DASHBOARD_QUERY_KEY] });
      queryClient.invalidateQueries({ queryKey: [DOCTOR_QUERY_KEY] });
    },
  });
}

export function useBulkApprove() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (ids: string[]) => {
      await Promise.all(ids.map((id) => approveDoctor(id)));
    },
    onSuccess: (_data, ids) => {
      notification.success({
        message: 'Approbation groupée',
        description: `${ids.length} médecin(s) approuvé(s).`,
        placement: 'topRight',
      });
    },
    onError: () => {
      notification.error({
        message: 'Erreur',
        description: "Certaines approbations ont échoué.",
        placement: 'topRight',
      });
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: [DOCTORS_QUERY_KEY] });
      queryClient.invalidateQueries({ queryKey: [DASHBOARD_QUERY_KEY] });
    },
  });
}

export function useBulkReject() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ ids, reason }: { ids: string[]; reason: string }) => {
      await Promise.all(ids.map((id) => rejectDoctor(id, reason)));
    },
    onSuccess: (_data, { ids }) => {
      notification.success({
        message: 'Refus groupé',
        description: `${ids.length} médecin(s) refusé(s).`,
        placement: 'topRight',
      });
    },
    onError: () => {
      notification.error({
        message: 'Erreur',
        description: 'Certains refus ont échoué.',
        placement: 'topRight',
      });
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: [DOCTORS_QUERY_KEY] });
      queryClient.invalidateQueries({ queryKey: [DASHBOARD_QUERY_KEY] });
    },
  });
}
