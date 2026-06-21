import { NavLink, useLocation } from 'react-router-dom';
import { LayoutDashboard, Users, Settings, ChevronLeft, ChevronRight } from 'lucide-react';
import { MedicineBoxOutlined } from '@ant-design/icons';
import { useAuthStore } from '@/store/authStore';
import { avatarColor, getInitials } from '@/utils/formatDate';

interface SidebarProps {
  collapsed: boolean;
  onToggle: () => void;
}

const navItems = [
  { to: '/dashboard', icon: LayoutDashboard, label: 'Tableau de bord' },
  { to: '/doctors', icon: Users, label: 'Médecins' },
  { to: '/settings', icon: Settings, label: 'Paramètres' },
];

export default function Sidebar({ collapsed, onToggle }: SidebarProps) {
  const location = useLocation();
  const admin = useAuthStore((s) => s.admin);
  const adminName = admin?.name ?? 'Admin';
  const initials = getInitials(adminName);
  const bg = avatarColor(adminName);

  return (
    <aside
      className="fixed left-0 top-0 z-40 flex h-screen flex-col bg-[#1A6B8A] text-white transition-all duration-300 ease-in-out"
      style={{ width: collapsed ? 64 : 240 }}
    >
      <div className="flex h-16 items-center gap-3 border-b border-white/10 px-4">
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-white/15">
          <MedicineBoxOutlined style={{ fontSize: 20 }} />
        </div>
        {!collapsed && (
          <div className="min-w-0">
            <p className="truncate text-sm font-bold leading-tight">HeadsApp</p>
            <span className="inline-block rounded bg-white/20 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wider">
              Admin
            </span>
          </div>
        )}
      </div>

      <nav className="flex-1 space-y-1 p-3">
        {navItems.map(({ to, icon: Icon, label }) => {
          const active = location.pathname.startsWith(to);
          return (
            <NavLink
              key={to}
              to={to}
              className={`flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors ${
                active
                  ? 'bg-white/20 text-white shadow-sm'
                  : 'text-white/90 hover:bg-white/12 hover:text-white'
              }`}
              title={collapsed ? label : undefined}
            >
              <Icon size={20} className="shrink-0" />
              {!collapsed && <span>{label}</span>}
            </NavLink>
          );
        })}
      </nav>

      <div className="border-t border-white/10 p-3">
        <div className="flex items-center gap-3 rounded-lg px-2 py-2">
          <div
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white"
            style={{ backgroundColor: bg }}
          >
            {initials}
          </div>
          {!collapsed && (
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">{adminName}</p>
              <p className="truncate text-xs text-white/60">{admin?.email}</p>
            </div>
          )}
        </div>
        <button
          type="button"
          onClick={onToggle}
          className="mt-2 flex w-full items-center justify-center rounded-lg py-2 text-white/70 transition-colors hover:bg-white/10 hover:text-white"
          aria-label={collapsed ? 'Développer la barre latérale' : 'Réduire la barre latérale'}
        >
          {collapsed ? <ChevronRight size={18} /> : <ChevronLeft size={18} />}
        </button>
      </div>
    </aside>
  );
}
