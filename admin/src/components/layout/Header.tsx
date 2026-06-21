import { Badge, Dropdown, Avatar } from 'antd';
import type { MenuProps } from 'antd';
import { BellOutlined, UserOutlined, LogoutOutlined } from '@ant-design/icons';
import { useAuthStore } from '@/store/authStore';
import { useAuth } from '@/hooks/useAuth';
import { useDashboard } from '@/hooks/useDashboard';
import { avatarColor, getInitials } from '@/utils/formatDate';
import { useNavigate } from 'react-router-dom';

interface HeaderProps {
  title: string;
  sidebarWidth: number;
}

export default function Header({ title, sidebarWidth }: HeaderProps) {
  const admin = useAuthStore((s) => s.admin);
  const { logout } = useAuth();
  const navigate = useNavigate();
  const { data } = useDashboard();

  const pendingCount = data?.stats.pending ?? 0;
  const adminName = admin?.name ?? 'Administrateur';
  const initials = getInitials(adminName);

  const menuItems: MenuProps['items'] = [
    {
      key: 'profile',
      icon: <UserOutlined />,
      label: 'Profil',
      onClick: () => navigate('/settings'),
    },
    { type: 'divider' },
    {
      key: 'logout',
      icon: <LogoutOutlined />,
      label: 'Déconnexion',
      danger: true,
      onClick: logout,
    },
  ];

  return (
    <header
      className="fixed top-0 z-30 flex h-16 items-center justify-between border-b border-gray-100 bg-surface px-6 transition-all duration-300"
      style={{ left: sidebarWidth, right: 0 }}
    >
      <h1 className="text-lg font-semibold text-text-primary">{title}</h1>

      <div className="flex items-center gap-4">
        <Badge count={pendingCount > 0 ? pendingCount : 0} size="small" offset={[-2, 2]} showZero={false}>
          <button
            type="button"
            className="flex h-9 w-9 items-center justify-center rounded-lg text-text-secondary transition-colors hover:bg-[#F0F4F8]"
            aria-label="Notifications"
            onClick={() => navigate('/doctors?status=pending')}
          >
            <BellOutlined style={{ fontSize: 18 }} />
          </button>
        </Badge>

        <Dropdown menu={{ items: menuItems }} placement="bottomRight" trigger={['click']}>
          <button
            type="button"
            className="flex items-center gap-2 rounded-lg px-2 py-1 transition-colors hover:bg-[#F0F4F8]"
          >
            <Avatar
              size={32}
              style={{ backgroundColor: avatarColor(adminName), fontSize: 13 }}
            >
              {initials}
            </Avatar>
            <span className="hidden text-sm font-medium text-text-primary sm:inline">
              {adminName}
            </span>
          </button>
        </Dropdown>
      </div>
    </header>
  );
}
