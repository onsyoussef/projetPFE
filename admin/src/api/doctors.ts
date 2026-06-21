import api, { isMockMode } from '@/api/axios';
import {
  mockGetDoctors,
  mockGetDoctorById,
  mockGetDashboardStats,
  mockApproveDoctorAsync,
  mockRejectDoctorAsync,
} from '@/mocks/doctors';
import type {
  DashboardResponse,
  Doctor,
  DoctorsListParams,
  DoctorsListResponse,
  VerificationDecisionResponse,
} from '@/types/doctor';

export async function getDoctors(
  params: DoctorsListParams = {},
): Promise<DoctorsListResponse> {
  if (isMockMode) {
    return mockGetDoctors(params);
  }

  const { data } = await api.get<DoctorsListResponse>('/admin/doctors', {
    params: {
      status: params.status ?? 'all',
      search: params.search ?? '',
      page: params.page ?? 1,
      pageSize: params.pageSize ?? 10,
    },
  });
  return data;
}

export async function getDoctorById(id: string): Promise<{ doctor: Doctor }> {
  if (isMockMode) {
    return mockGetDoctorById(id);
  }

  const { data } = await api.get<{ doctor: Doctor }>(`/admin/doctors/${id}`);
  return data;
}

export async function approveDoctor(
  id: string,
): Promise<VerificationDecisionResponse> {
  if (isMockMode) {
    return mockApproveDoctorAsync(id);
  }

  const { data } = await api.patch<VerificationDecisionResponse>(
    `/admin/doctors/${id}/verification`,
    { status: 'verified' },
  );
  return data;
}

export async function rejectDoctor(
  id: string,
  reason: string,
): Promise<VerificationDecisionResponse> {
  if (isMockMode) {
    return mockRejectDoctorAsync(id, reason);
  }

  const { data } = await api.patch<VerificationDecisionResponse>(
    `/admin/doctors/${id}/verification`,
    { status: 'rejected', reason },
  );
  return data;
}

export async function getDashboardStats(): Promise<DashboardResponse> {
  if (isMockMode) {
    return mockGetDashboardStats();
  }

  const { data } = await api.get<DashboardResponse>('/admin/dashboard/stats');
  return data;
}
