import api, { isMockMode } from '@/api/axios';
import type { LoginResponse } from '@/types/doctor';

export async function loginAdmin(
  email: string,
  password: string,
): Promise<LoginResponse> {
  if (isMockMode) {
    await new Promise((r) => setTimeout(r, 600));
    if (email && password.length >= 4) {
      return {
        message: 'Connexion réussie.',
        token: 'mock-jwt-token-headsapp-admin',
        admin: {
          id: 'admin',
          email,
          name: 'Administrateur HeadsApp',
        },
      };
    }
    throw new Error('Identifiants invalides');
  }

  const { data } = await api.post<LoginResponse>('/admin/auth/login', {
    email,
    password,
  });
  return data;
}
