import { useState } from 'react';
import {
  Drawer,
  Descriptions,
  Timeline,
  Button,
  Popconfirm,
  Input,
  Spin,
  List,
} from 'antd';
import { DownloadOutlined, CheckOutlined, CloseOutlined } from '@ant-design/icons';
import DoctorAvatar from '@/components/doctors/DoctorAvatar';
import StatusBadge from '@/components/doctors/StatusBadge';
import { useDoctorDetail, useApproveDoctor, useRejectDoctor } from '@/hooks/useDoctors';
import { formatDate, formatDateTime } from '@/utils/formatDate';
import type { DoctorStatus } from '@/types/doctor';

interface DoctorDrawerProps {
  doctorId: string | null;
  open: boolean;
  onClose: () => void;
}

function buildTimeline(status: DoctorStatus, createdAt: string, reviewedAt?: string | null) {
  const items = [
    {
      color: '#E67E22',
      children: (
        <div>
          <p className="font-medium text-text-primary">Inscription soumise</p>
          <p className="text-xs text-text-secondary">{formatDateTime(createdAt)}</p>
        </div>
      ),
    },
  ];

  if (status === 'approved' && reviewedAt) {
    items.push({
      color: '#2ECC9A',
      children: (
        <div>
          <p className="font-medium text-text-primary">Compte approuvé</p>
          <p className="text-xs text-text-secondary">{formatDateTime(reviewedAt)}</p>
        </div>
      ),
    });
  }

  if (status === 'rejected' && reviewedAt) {
    items.push({
      color: '#E74C3C',
      children: (
        <div>
          <p className="font-medium text-text-primary">Inscription refusée</p>
          <p className="text-xs text-text-secondary">{formatDateTime(reviewedAt)}</p>
        </div>
      ),
    });
  }

  if (status === 'pending') {
    items.push({
      color: '#CBD5E0',
      children: (
        <p className="text-text-secondary">En attente de validation</p>
      ),
    });
  }

  return items;
}

export default function DoctorDrawer({ doctorId, open, onClose }: DoctorDrawerProps) {
  const [rejectMode, setRejectMode] = useState(false);
  const [rejectReason, setRejectReason] = useState('');

  const { data, isLoading } = useDoctorDetail(doctorId);
  const approveMutation = useApproveDoctor();
  const rejectMutation = useRejectDoctor();

  const doctor = data?.doctor;
  const isPending = doctor?.status === 'pending';
  const isActionLoading = approveMutation.isPending || rejectMutation.isPending;

  const handleClose = () => {
    setRejectMode(false);
    setRejectReason('');
    onClose();
  };

  const handleApprove = () => {
    if (!doctorId) return;
    approveMutation.mutate(doctorId, { onSuccess: handleClose });
  };

  const handleReject = () => {
    if (!doctorId || !rejectReason.trim()) return;
    rejectMutation.mutate(
      { id: doctorId, reason: rejectReason.trim() },
      { onSuccess: handleClose },
    );
  };

  return (
    <Drawer
      title="Détails du médecin"
      open={open}
      onClose={handleClose}
      width={480}
      destroyOnClose
      styles={{ body: { paddingBottom: 80 } }}
      footer={
        doctor && isPending ? (
          <div className="space-y-3">
            {rejectMode && (
              <Input.TextArea
                rows={3}
                placeholder="Motif du refus (obligatoire)"
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
              />
            )}
            <div className="flex gap-3">
              {!rejectMode ? (
                <>
                  <Popconfirm
                    title="Approuver ce médecin ?"
                    description="Le médecin pourra accéder à l'application mobile."
                    onConfirm={handleApprove}
                    okText="Approuver"
                    cancelText="Annuler"
                    okButtonProps={{ style: { background: '#2ECC9A', borderColor: '#2ECC9A' } }}
                  >
                    <Button
                      type="primary"
                      icon={<CheckOutlined />}
                      loading={approveMutation.isPending}
                      className="flex-1"
                      style={{ background: '#2ECC9A', borderColor: '#2ECC9A', borderRadius: 8 }}
                    >
                      Approuver
                    </Button>
                  </Popconfirm>
                  <Button
                    danger
                    icon={<CloseOutlined />}
                    className="flex-1"
                    style={{ borderRadius: 8 }}
                    onClick={() => setRejectMode(true)}
                  >
                    Refuser
                  </Button>
                </>
              ) : (
                <>
                  <Button onClick={() => setRejectMode(false)} className="flex-1" style={{ borderRadius: 8 }}>
                    Annuler
                  </Button>
                  <Popconfirm
                    title="Confirmer le refus ?"
                    description="Le médecin sera notifié du motif de refus."
                    onConfirm={handleReject}
                    okText="Confirmer"
                    cancelText="Retour"
                    disabled={!rejectReason.trim()}
                  >
                    <Button
                      danger
                      type="primary"
                      loading={rejectMutation.isPending}
                      disabled={!rejectReason.trim()}
                      className="flex-1"
                      style={{ borderRadius: 8 }}
                    >
                      Confirmer le refus
                    </Button>
                  </Popconfirm>
                </>
              )}
            </div>
          </div>
        ) : null
      }
    >
      {isLoading ? (
        <div className="flex justify-center py-20">
          <Spin size="large" />
        </div>
      ) : doctor ? (
        <div className="space-y-6">
          <div className="flex items-center gap-4">
            <DoctorAvatar name={doctor.fullName} size={64} />
            <div>
              <h2 className="text-xl font-bold text-text-primary">{doctor.fullName}</h2>
              <p className="text-text-secondary">{doctor.specialty}</p>
              <div className="mt-2">
                <StatusBadge status={doctor.status} />
              </div>
            </div>
          </div>

          <section>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-text-secondary">
              Informations personnelles
            </h3>
            <Descriptions column={1} size="small" bordered>
              <Descriptions.Item label="Email">{doctor.email}</Descriptions.Item>
              <Descriptions.Item label="Téléphone">{doctor.phone || '—'}</Descriptions.Item>
              <Descriptions.Item label="Ville">{doctor.city || doctor.governorate || '—'}</Descriptions.Item>
              <Descriptions.Item label="Date de naissance">{formatDate(doctor.birthdate)}</Descriptions.Item>
            </Descriptions>
          </section>

          <section>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-text-secondary">
              Informations professionnelles
            </h3>
            <Descriptions column={1} size="small" bordered>
              <Descriptions.Item label="N° d'ordre">{doctor.orderNumber || '—'}</Descriptions.Item>
              <Descriptions.Item label="Expérience">
                {doctor.yearsExperience} an{doctor.yearsExperience > 1 ? 's' : ''}
              </Descriptions.Item>
              <Descriptions.Item label="Établissement">
                {doctor.hospitalOrClinic || '—'}
              </Descriptions.Item>
            </Descriptions>
          </section>

          {doctor.documents && doctor.documents.length > 0 && (
            <section>
              <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-text-secondary">
                Documents
              </h3>
              <List
                size="small"
                bordered
                dataSource={doctor.documents}
                renderItem={(doc) => (
                  <List.Item
                    actions={[
                      <Button
                        key="dl"
                        type="link"
                        icon={<DownloadOutlined />}
                        href={doc.url}
                        target="_blank"
                        disabled={doc.url === '#'}
                      >
                        Télécharger
                      </Button>,
                    ]}
                  >
                    {doc.label}
                  </List.Item>
                )}
              />
            </section>
          )}

          {doctor.rejectionReason && (
            <section className="rounded-lg border border-red-200 bg-red-50 p-3">
              <p className="text-sm font-medium text-red-700">Motif de refus</p>
              <p className="mt-1 text-sm text-red-600">{doctor.rejectionReason}</p>
            </section>
          )}

          <section>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-text-secondary">
              Historique du statut
            </h3>
            <Timeline items={buildTimeline(doctor.status, doctor.createdAt, doctor.reviewedAt)} />
          </section>
        </div>
      ) : null}
    </Drawer>
  );
}
