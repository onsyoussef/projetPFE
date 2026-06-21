import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { ConfigProvider, App as AntApp } from 'antd';
import frFR from 'antd/locale/fr_FR';
import AppLayout from '@/components/layout/AppLayout';
import ProtectedRoute from '@/components/shared/ProtectedRoute';
import QueryErrorBoundary from '@/components/shared/QueryErrorBoundary';
import Login from '@/pages/Login';
import Dashboard from '@/pages/Dashboard';
import Doctors from '@/pages/Doctors';
import Settings from '@/pages/Settings';

const theme = {
  token: {
    colorPrimary: '#1A6B8A',
    colorSuccess: '#2ECC9A',
    colorError: '#E74C3C',
    borderRadius: 8,
    fontFamily: "'Inter', system-ui, sans-serif",
  },
};

export default function App() {
  return (
    <ConfigProvider locale={frFR} theme={theme}>
      <AntApp>
        <BrowserRouter>
          <QueryErrorBoundary>
            <Routes>
              <Route path="/login" element={<Login />} />
              <Route
                path="/"
                element={
                  <ProtectedRoute>
                    <AppLayout />
                  </ProtectedRoute>
                }
              >
                <Route index element={<Navigate to="/dashboard" replace />} />
                <Route path="dashboard" element={<Dashboard />} />
                <Route path="doctors" element={<Doctors />} />
                <Route path="settings" element={<Settings />} />
              </Route>
              <Route path="*" element={<Navigate to="/dashboard" replace />} />
            </Routes>
          </QueryErrorBoundary>
        </BrowserRouter>
      </AntApp>
    </ConfigProvider>
  );
}
