import { useMemo, useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  Table,
  Input,
  Tabs,
  Button,
  Popconfirm,
  Space,
  Modal,
} from 'antd';
import type { TableProps } from 'antd';
import { SearchOutlined, EyeOutlined, CheckOutlined, CloseOutlined } from '@ant-design/icons';
import DoctorAvatar from '@/components/doctors/DoctorAvatar';
import StatusBadge from '@/components/doctors/StatusBadge';
import EmptyState from '@/components/shared/EmptyState';
import LoadingSkeleton from '@/components/shared/LoadingSkeleton';
import {
  useDoctorsList,
  useApproveDoctor,
  useRejectDoctor,
  useBulkApprove,
  useBulkReject,
} from '@/hooks/useDoctors';
import { formatDate } from '@/utils/formatDate';
import type { Doctor, DoctorStatus } from '@/types/doctor';

interface DoctorTableProps {
  onViewDoctor: (id: string) => void;
}

type StatusFilter = DoctorStatus | 'all';

export default function DoctorTable({ onViewDoctor }: DoctorTableProps) {
  const [searchParams] = useSearchParams();
  const initialStatus = searchParams.get('status') as StatusFilter | null;
  const [statusFilter, setStatusFilter] = useState<StatusFilter>(
    initialStatus && ['all', 'pending', 'approved', 'rejected'].includes(initialStatus)
      ? initialStatus
      : 'all',
  );
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [selectedRowKeys, setSelectedRowKeys] = useState<string[]>([]);
  const [bulkRejectOpen, setBulkRejectOpen] = useState(false);
  const [bulkRejectReason, setBulkRejectReason] = useState('');

  useEffect(() => {
    const status = searchParams.get('status') as StatusFilter | null;
    if (status && ['pending', 'approved', 'rejected', 'all'].includes(status)) {
      setStatusFilter(status);
      setPage(1);
    }
  }, [searchParams]);

  const { data, isLoading, isError, refetch } = useDoctorsList({
    status: statusFilter,
    search,
    page,
    pageSize: 10,
  });

  const approveMutation = useApproveDoctor();
  const rejectMutation = useRejectDoctor();
  const bulkApprove = useBulkApprove();
  const bulkReject = useBulkReject();

  const tabItems = [
    { key: 'all', label: 'Tous' },
    { key: 'pending', label: 'En attente' },
    { key: 'approved', label: 'Approuvés' },
    { key: 'rejected', label: 'Refusés' },
  ];

  const columns: TableProps<Doctor>['columns'] = useMemo(
    () => [
      {
        title: 'Médecin',
        dataIndex: 'fullName',
        key: 'fullName',
        sorter: (a, b) => a.fullName.localeCompare(b.fullName, 'fr'),
        render: (_: string, record) => (
          <div className="flex items-center gap-3">
            <DoctorAvatar name={record.fullName} />
            <span className="font-medium text-text-primary">{record.fullName}</span>
          </div>
        ),
      },
      {
        title: 'Spécialité',
        dataIndex: 'specialty',
        key: 'specialty',
        sorter: (a, b) => a.specialty.localeCompare(b.specialty, 'fr'),
      },
      {
        title: 'Ville',
        dataIndex: 'city',
        key: 'city',
        sorter: (a, b) => (a.city || '').localeCompare(b.city || '', 'fr'),
      },
      {
        title: 'Inscription',
        dataIndex: 'createdAt',
        key: 'createdAt',
        sorter: (a, b) =>
          new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime(),
        defaultSortOrder: 'descend',
        render: (date: string) => formatDate(date),
      },
      {
        title: 'Statut',
        dataIndex: 'status',
        key: 'status',
        render: (status: DoctorStatus) => <StatusBadge status={status} />,
      },
      {
        title: 'Actions',
        key: 'actions',
        width: 220,
        render: (_: unknown, record) => (
          <Space size="small">
            <Button
              type="link"
              size="small"
              icon={<EyeOutlined />}
              onClick={() => onViewDoctor(record.id)}
            >
              Voir
            </Button>
            {record.status === 'pending' && (
              <>
                <Popconfirm
                  title="Approuver ce médecin ?"
                  onConfirm={() => approveMutation.mutate(record.id)}
                  okText="Oui"
                  cancelText="Non"
                >
                  <Button type="link" size="small" style={{ color: '#2ECC9A' }} icon={<CheckOutlined />}>
                    Approuver
                  </Button>
                </Popconfirm>
                <Popconfirm
                  title="Refuser ce médecin ?"
                  description="Utilisez « Voir » pour saisir un motif détaillé."
                  onConfirm={() =>
                    rejectMutation.mutate({
                      id: record.id,
                      reason: 'Refus administratif rapide',
                    })
                  }
                  okText="Refuser"
                  cancelText="Annuler"
                  okButtonProps={{ danger: true }}
                >
                  <Button type="link" size="small" danger icon={<CloseOutlined />}>
                    Refuser
                  </Button>
                </Popconfirm>
              </>
            )}
          </Space>
        ),
      },
    ],
    [approveMutation, rejectMutation, onViewDoctor],
  );

  const pendingSelected = selectedRowKeys.filter((id) => {
    const doc = data?.doctors.find((d) => d.id === id);
    return doc?.status === 'pending';
  });

  if (isError) {
    return (
      <div className="rounded-xl bg-surface p-8 text-center shadow-card">
        <p className="text-text-secondary">Erreur lors du chargement des médecins.</p>
        <Button type="primary" className="mt-4" onClick={() => refetch()}>
          Réessayer
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <Input
          placeholder="Rechercher par nom, email ou spécialité…"
          prefix={<SearchOutlined className="text-text-secondary" />}
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setPage(1);
          }}
          allowClear
          className="max-w-md"
          style={{ borderRadius: 8 }}
        />
        {pendingSelected.length > 0 && (
          <Space>
            <Popconfirm
              title={`Approuver ${pendingSelected.length} médecin(s) ?`}
              onConfirm={() => {
                bulkApprove.mutate(pendingSelected, {
                  onSuccess: () => setSelectedRowKeys([]),
                });
              }}
            >
              <Button
                type="primary"
                style={{ background: '#2ECC9A', borderColor: '#2ECC9A', borderRadius: 8 }}
                loading={bulkApprove.isPending}
              >
                Tout approuver ({pendingSelected.length})
              </Button>
            </Popconfirm>
            <Button
              danger
              style={{ borderRadius: 8 }}
              onClick={() => setBulkRejectOpen(true)}
            >
              Tout refuser ({pendingSelected.length})
            </Button>
          </Space>
        )}
      </div>

      <Tabs
        activeKey={statusFilter}
        onChange={(key) => {
          setStatusFilter(key as StatusFilter);
          setPage(1);
          setSelectedRowKeys([]);
        }}
        items={tabItems}
      />

      {isLoading ? (
        <LoadingSkeleton type="table" rows={8} />
      ) : (
        <div className="rounded-xl bg-surface shadow-card overflow-hidden">
          <Table<Doctor>
            rowKey="id"
            columns={columns}
            dataSource={data?.doctors ?? []}
            rowSelection={{
              selectedRowKeys,
              onChange: (keys) => setSelectedRowKeys(keys as string[]),
            }}
            pagination={{
              current: page,
              pageSize: 10,
              total: data?.total ?? 0,
              onChange: (p) => setPage(p),
              showTotal: (total) => `${total} médecin(s)`,
              showSizeChanger: false,
            }}
            locale={{
              emptyText: <EmptyState />,
            }}
            scroll={{ x: 800 }}
          />
        </div>
      )}

      <Modal
        title="Refus groupé"
        open={bulkRejectOpen}
        onCancel={() => {
          setBulkRejectOpen(false);
          setBulkRejectReason('');
        }}
        onOk={() => {
          if (!bulkRejectReason.trim()) return;
          bulkReject.mutate(
            { ids: pendingSelected, reason: bulkRejectReason.trim() },
            {
              onSuccess: () => {
                setBulkRejectOpen(false);
                setBulkRejectReason('');
                setSelectedRowKeys([]);
              },
            },
          );
        }}
        okText="Confirmer le refus"
        okButtonProps={{ danger: true, disabled: !bulkRejectReason.trim() }}
        cancelText="Annuler"
      >
        <p className="mb-3 text-sm text-text-secondary">
          Motif appliqué à {pendingSelected.length} médecin(s) :
        </p>
        <Input.TextArea
          rows={4}
          value={bulkRejectReason}
          onChange={(e) => setBulkRejectReason(e.target.value)}
          placeholder="Motif du refus (obligatoire)"
        />
      </Modal>
    </div>
  );
}
