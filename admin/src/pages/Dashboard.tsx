import { Button, Popconfirm, Result } from 'antd';
import {
  UserOutlined,
  ClockCircleOutlined,
  CheckCircleOutlined,
  CloseCircleOutlined,
  CheckOutlined,
  CloseOutlined,
} from '@ant-design/icons';
import { Activity, Clock3, Inbox } from 'lucide-react';
import KpiCard from '@/components/shared/KpiCard';
import LoadingSkeleton from '@/components/shared/LoadingSkeleton';
import EmptyState from '@/components/shared/EmptyState';
import DoctorAvatar from '@/components/doctors/DoctorAvatar';
import { useDashboard } from '@/hooks/useDashboard';
import { useApproveDoctor, useRejectDoctor } from '@/hooks/useDoctors';
import { formatDateTime } from '@/utils/formatDate';
import { useNavigate } from 'react-router-dom';

export default function Dashboard() {
  const { data, isLoading, isError, refetch } = useDashboard();
  const approveMutation = useApproveDoctor();
  const rejectMutation = useRejectDoctor();
  const navigate = useNavigate();

  if (isLoading) {
    return <LoadingSkeleton />;
  }

  if (isError || !data) {
    return (
      <Result
        status="error"
        title="Impossible de charger le tableau de bord"
        subTitle="Vérifiez que le backend est démarré et que vous êtes connecté."
        extra={
          <Button type="primary" onClick={() => refetch()}>
            Réessayer
          </Button>
        }
      />
    );
  }

  const { stats, recentPending, activity } = data;
  const isEmpty = stats.total === 0;

  const pct = (n: number) =>
    stats.total > 0 ? Math.round((n / stats.total) * 100) : 0;

  return (
    <div className="dashboard-page page-transition">
      <header className="dashboard-hero">
        <div>
          <p className="dashboard-hero-eyebrow">Vue d&apos;ensemble</p>
          <h2 className="dashboard-hero-title">Validation des comptes médecins</h2>
          <p className="dashboard-hero-subtitle">
            {isEmpty
              ? 'Aucune inscription pour le moment. Les nouvelles demandes apparaîtront ici.'
              : stats.pending > 0
                ? `${stats.pending} demande${stats.pending > 1 ? 's' : ''} en attente de votre validation.`
                : 'Toutes les demandes en cours ont été traitées.'}
          </p>
        </div>
        {stats.pending > 0 && (
          <Button
            type="primary"
            size="large"
            className="dashboard-hero-cta"
            onClick={() => navigate('/doctors?status=pending')}
          >
            Traiter les demandes
          </Button>
        )}
      </header>

      <div className="kpi-grid">
        <KpiCard
          title="Total médecins"
          value={stats.total}
          subtitle={
            isEmpty
              ? 'Aucun compte inscrit'
              : 'Comptes inscrits sur la plateforme'
          }
          color="#1A6B8A"
          bgColor="#E8F4F8"
          accentColor="#1A6B8A"
          icon={<UserOutlined />}
          onClick={() => navigate('/doctors')}
        />
        <KpiCard
          title="En attente"
          value={stats.pending}
          subtitle={
            stats.pending > 0
              ? `${pct(stats.pending)}% · Action requise`
              : 'Aucune validation en cours'
          }
          color="#E67E22"
          bgColor="#FEF3E2"
          accentColor="#E67E22"
          icon={<ClockCircleOutlined />}
          onClick={() => navigate('/doctors?status=pending')}
        />
        <KpiCard
          title="Approuvés"
          value={stats.approved}
          subtitle={
            isEmpty ? '—' : `${pct(stats.approved)}% du total`
          }
          color="#2ECC9A"
          bgColor="#E8F8F0"
          accentColor="#2ECC9A"
          icon={<CheckCircleOutlined />}
          onClick={() => navigate('/doctors?status=approved')}
        />
        <KpiCard
          title="Refusés"
          value={stats.rejected}
          subtitle={
            isEmpty ? '—' : `${pct(stats.rejected)}% du total`
          }
          color="#E74C3C"
          bgColor="#FDEDEC"
          accentColor="#E74C3C"
          icon={<CloseCircleOutlined />}
          onClick={() => navigate('/doctors?status=rejected')}
        />
      </div>

      {isEmpty ? (
        <section className="dashboard-panel dashboard-panel-empty">
          <EmptyState
            icon={<Inbox size={28} className="text-[#1A6B8A]" />}
            title="Tableau de bord vide"
            description="Lorsqu'un médecin s'inscrit via l'application, sa demande apparaîtra ici pour approbation."
          />
        </section>
      ) : (
        <div className="dashboard-panels-grid">
          <section className="dashboard-panel">
            <div className="dashboard-panel-header">
              <div>
                <h3 className="dashboard-panel-title">Médecins en attente récents</h3>
                <p className="dashboard-panel-subtitle">
                  Dernières inscriptions à valider
                </p>
              </div>
              <Button type="link" onClick={() => navigate('/doctors?status=pending')}>
                Voir tout
              </Button>
            </div>

            {recentPending.length === 0 ? (
              <EmptyState
                icon={<Clock3 size={26} className="text-[#E67E22]" />}
                title="Aucun médecin en attente"
                description="Les nouvelles demandes d'inscription s'afficheront dans cette section."
              />
            ) : (
              <ul className="dashboard-pending-list">
                {recentPending.map((doctor) => (
                  <li key={doctor.id} className="dashboard-pending-item">
                    <button
                      type="button"
                      className="dashboard-pending-main"
                      onClick={() => navigate(`/doctors?status=pending`)}
                    >
                      <DoctorAvatar name={doctor.fullName} size={40} />
                      <div className="min-w-0 text-left">
                        <p className="dashboard-pending-name">{doctor.fullName}</p>
                        <p className="dashboard-pending-meta">
                          {doctor.specialty}
                          {doctor.city ? ` · ${doctor.city}` : ''}
                        </p>
                      </div>
                    </button>
                    <div className="dashboard-pending-actions">
                      <Popconfirm
                        title="Approuver ce médecin ?"
                        okText="Approuver"
                        cancelText="Annuler"
                        onConfirm={() => approveMutation.mutate(doctor.id)}
                      >
                        <Button
                          type="primary"
                          size="middle"
                          icon={<CheckOutlined />}
                          loading={approveMutation.isPending}
                          className="dashboard-btn-approve"
                        />
                      </Popconfirm>
                      <Popconfirm
                        title="Refuser ce médecin ?"
                        okText="Refuser"
                        cancelText="Annuler"
                        onConfirm={() =>
                          rejectMutation.mutate({
                            id: doctor.id,
                            reason: 'Refus depuis le tableau de bord',
                          })
                        }
                      >
                        <Button
                          size="middle"
                          danger
                          icon={<CloseOutlined />}
                          loading={rejectMutation.isPending}
                          className="dashboard-btn-reject"
                        />
                      </Popconfirm>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="dashboard-panel">
            <div className="dashboard-panel-header">
              <div>
                <h3 className="dashboard-panel-title">Activité récente</h3>
                <p className="dashboard-panel-subtitle">
                  Dernières décisions de validation
                </p>
              </div>
            </div>

            {activity.length === 0 ? (
              <EmptyState
                icon={<Activity size={26} className="text-[#718096]" />}
                title="Aucune activité récente"
                description="Les approbations et refus apparaîtront ici."
              />
            ) : (
              <ul className="dashboard-activity-list">
                {activity.map((item) => {
                  const approved = item.action === 'approved';
                  return (
                    <li key={item.id} className="dashboard-activity-item">
                      <span
                        className={`dashboard-activity-dot ${
                          approved
                            ? 'dashboard-activity-dot--approved'
                            : 'dashboard-activity-dot--rejected'
                        }`}
                        aria-hidden
                      />
                      <div className="dashboard-activity-body">
                        <p className="dashboard-activity-text">
                          <span className="font-semibold">{item.doctorName}</span>
                          {approved ? ' a été approuvé' : ' a été refusé'}
                        </p>
                        <p className="dashboard-activity-time">
                          {formatDateTime(item.at)}
                        </p>
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        </div>
      )}
    </div>
  );
}
