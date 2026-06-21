import { avatarColor, getInitials } from '@/utils/formatDate';

interface DoctorAvatarProps {
  name: string;
  size?: number;
}

export default function DoctorAvatar({ name, size = 40 }: DoctorAvatarProps) {
  const initials = getInitials(name);
  const bg = avatarColor(name);

  return (
    <div
      className="flex shrink-0 items-center justify-center rounded-full font-semibold text-white"
      style={{
        width: size,
        height: size,
        backgroundColor: bg,
        fontSize: size * 0.35,
      }}
      aria-hidden
    >
      {initials}
    </div>
  );
}
