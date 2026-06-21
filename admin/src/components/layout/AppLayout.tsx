import { useState } from 'react';
import { Outlet, useLocation } from 'react-router-dom';
import Sidebar from '@/components/layout/Sidebar';
import Header from '@/components/layout/Header';

const pageTitles: Record<string, string> = {
  '/dashboard': 'Tableau de bord',
  '/doctors': 'Gestion des médecins',
  '/settings': 'Paramètres',
};

export default function AppLayout() {
  const [collapsed, setCollapsed] = useState(false);
  const location = useLocation();
  const sidebarWidth = collapsed ? 64 : 240;

  const basePath = Object.keys(pageTitles).find((p) =>
    location.pathname.startsWith(p),
  );
  const title = pageTitles[basePath ?? ''] ?? 'HeadsApp Admin';

  return (
    <div className="min-h-screen bg-background">
      <Sidebar collapsed={collapsed} onToggle={() => setCollapsed((c) => !c)} />
      <Header title={title} sidebarWidth={sidebarWidth} />
      <main
        className="page-transition min-h-screen pt-20 transition-all duration-300"
        style={{ marginLeft: sidebarWidth, padding: '24px 28px 32px' }}
      >
        <Outlet />
      </main>
    </div>
  );
}
