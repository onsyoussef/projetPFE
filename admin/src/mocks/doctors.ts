import type { Doctor, DoctorStatus } from '@/types/doctor';

/** Données de démo vides — l'admin utilise l'API backend par défaut. */
export const mockDoctors: Doctor[] = [];

let mockStore: Doctor[] = [];

export function resetMockStore() {
  mockStore = [];
}

export function getMockDoctors(params: {
  status?: DoctorStatus | 'all';
  search?: string;
  page?: number;
  pageSize?: number;
}) {
  const { status = 'all', search = '', page = 1, pageSize = 10 } = params;
  let filtered = [...mockStore];

  if (status !== 'all') {
    filtered = filtered.filter((d) => d.status === status);
  }

  if (search.trim()) {
    const q = search.trim().toLowerCase();
    filtered = filtered.filter(
      (d) =>
        d.fullName.toLowerCase().includes(q) ||
        d.email.toLowerCase().includes(q) ||
        d.specialty.toLowerCase().includes(q) ||
        d.city.toLowerCase().includes(q),
    );
  }

  filtered.sort(
    (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
  );

  const total = filtered.length;
  const start = (page - 1) * pageSize;
  const doctors = filtered.slice(start, start + pageSize);

  return { doctors, total, page, pageSize };
}

export function getMockDoctorById(id: string): Doctor | undefined {
  return mockStore.find((d) => d.id === id);
}

export function mockApproveDoctor(id: string): Doctor {
  const idx = mockStore.findIndex((d) => d.id === id);
  if (idx === -1) throw new Error('Médecin introuvable');
  mockStore[idx] = {
    ...mockStore[idx],
    status: 'approved',
    reviewedAt: new Date().toISOString(),
    rejectionReason: null,
  };
  return mockStore[idx];
}

export function mockRejectDoctor(id: string, reason: string): Doctor {
  const idx = mockStore.findIndex((d) => d.id === id);
  if (idx === -1) throw new Error('Médecin introuvable');
  mockStore[idx] = {
    ...mockStore[idx],
    status: 'rejected',
    reviewedAt: new Date().toISOString(),
    rejectionReason: reason,
  };
  return mockStore[idx];
}

export function getMockDashboardStats() {
  const pending = mockStore.filter((d) => d.status === 'pending');
  const approved = mockStore.filter((d) => d.status === 'approved');
  const rejected = mockStore.filter((d) => d.status === 'rejected');

  const recentPending = [...pending]
    .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
    .slice(0, 5);

  const activity = mockStore
    .filter((d) => d.reviewedAt)
    .sort((a, b) => new Date(b.reviewedAt!).getTime() - new Date(a.reviewedAt!).getTime())
    .slice(0, 8)
    .map((d) => ({
      id: d.id,
      doctorName: d.fullName,
      action: d.status === 'approved' ? ('approved' as const) : ('rejected' as const),
      at: d.reviewedAt!,
    }));

  return {
    stats: {
      total: mockStore.length,
      pending: pending.length,
      approved: approved.length,
      rejected: rejected.length,
    },
    recentPending,
    activity,
  };
}

function delay(ms = 400) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function mockGetDoctors(params: Parameters<typeof getMockDoctors>[0]) {
  await delay();
  return getMockDoctors(params);
}

export async function mockGetDoctorById(id: string) {
  await delay();
  const doctor = getMockDoctorById(id);
  if (!doctor) throw new Error('Médecin introuvable');
  return { doctor };
}

export async function mockGetDashboardStats() {
  await delay();
  return getMockDashboardStats();
}

export async function mockApproveDoctorAsync(id: string) {
  await delay(300);
  const doctor = mockApproveDoctor(id);
  return { message: 'Compte médecin approuvé.', doctor };
}

export async function mockRejectDoctorAsync(id: string, reason: string) {
  await delay(300);
  const doctor = mockRejectDoctor(id, reason);
  return { message: 'Inscription refusée.', doctor };
}
