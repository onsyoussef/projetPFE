import { useMutation } from '@tanstack/react-query';
import { notification } from 'antd';
import { loginAdmin } from '@/api/auth';
import { useAuthStore } from '@/store/authStore';
import { useNavigate } from 'react-router-dom';

export function useAuth() {
  const token = useAuthStore((s) => s.token);
  const admin = useAuthStore((s) => s.admin);
  const setAuth = useAuthStore((s) => s.setAuth);
  const logout = useAuthStore((s) => s.logout);
  const navigate = useNavigate();

  const loginMutation = useMutation({
    mutationFn: ({
      email,
      password,
    }: {
      email: string;
      password: string;
      rememberMe: boolean;
    }) => loginAdmin(email, password),
    onSuccess: (data, variables) => {
      setAuth(data.token, data.admin, variables.rememberMe);
      notification.success({
        message: 'Connexion réussie',
        description: `Bienvenue, ${data.admin.name}`,
        placement: 'topRight',
      });
      navigate('/dashboard', { replace: true });
    },
    onError: (error: unknown) => {
      const message =
        (error as { response?: { data?: { message?: string } } })?.response?.data
          ?.message ||
        (error instanceof Error ? error.message : 'Identifiants invalides.');
      notification.error({
        message: 'Échec de la connexion',
        description: message,
        placement: 'topRight',
      });
    },
  });

  const handleLogout = () => {
    logout();
    navigate('/login', { replace: true });
    notification.info({
      message: 'Déconnexion',
      description: 'Vous avez été déconnecté.',
      placement: 'topRight',
    });
  };

  return {
    token,
    admin,
    isAuthenticated: !!token,
    login: loginMutation.mutate,
    isLoggingIn: loginMutation.isPending,
    logout: handleLogout,
  };
}
