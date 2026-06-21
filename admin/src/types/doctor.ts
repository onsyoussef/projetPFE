export type DoctorStatus = 'pending' | 'approved' | 'rejected';

export interface DoctorDocument {
  id: string;
  label: string;
  url: string;
  type: string;
}

export interface Doctor {
  id: string;
  fullName: string;
  email: string;
  phone: string;
  specialty: string;
  city: string;
  governorate?: string;
  address?: string;
  country?: string;
  orderNumber?: string | null;
  yearsExperience: number;
  hospitalOrClinic?: string | null;
  diplomaPath?: string | null;
  photoPath?: string | null;
  birthdate?: string | null;
  status: DoctorStatus;
  verificationStatus?: 'pending' | 'verified' | 'rejected';
  rejectionReason?: string | null;
  reviewedAt?: string | null;
  createdAt: string;
  updatedAt?: string;
  documents?: DoctorDocument[];
}

export interface DoctorsListParams {
  status?: DoctorStatus | 'all';
  search?: string;
  page?: number;
  pageSize?: number;
}

export interface DoctorsListResponse {
  doctors: Doctor[];
  total: number;
  page: number;
  pageSize: number;
}

export interface DashboardStats {
  total: number;
  pending: number;
  approved: number;
  rejected: number;
}

export interface ActivityItem {
  id: string;
  doctorName: string;
  action: 'approved' | 'rejected';
  at: string;
}

export interface DashboardResponse {
  stats: DashboardStats;
  recentPending: Doctor[];
  activity: ActivityItem[];
}

export interface AdminUser {
  id: string;
  email: string;
  name: string;
}

export interface LoginResponse {
  message: string;
  token: string;
  admin: AdminUser;
}

export interface VerificationNotification {
  emailSent: boolean;
  pushSent: boolean;
  errors: string[];
}

export interface VerificationDecisionResponse {
  message: string;
  doctor: Doctor;
  notification?: VerificationNotification;
}
