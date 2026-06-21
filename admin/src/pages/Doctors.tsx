import { useState } from 'react';
import DoctorTable from '@/components/doctors/DoctorTable';
import DoctorDrawer from '@/components/doctors/DoctorDrawer';

export default function Doctors() {
  const [selectedDoctorId, setSelectedDoctorId] = useState<string | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);

  const handleViewDoctor = (id: string) => {
    setSelectedDoctorId(id);
    setDrawerOpen(true);
  };

  const handleCloseDrawer = () => {
    setDrawerOpen(false);
    setSelectedDoctorId(null);
  };

  return (
    <div className="page-transition">
      <DoctorTable onViewDoctor={handleViewDoctor} />
      <DoctorDrawer
        doctorId={selectedDoctorId}
        open={drawerOpen}
        onClose={handleCloseDrawer}
      />
    </div>
  );
}
