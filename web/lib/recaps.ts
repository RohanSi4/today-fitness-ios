export type MovementMetric = {
  label: string;
  value: string;
  average: string;
  delta: string;
  progress: number;
  tone: "teal" | "indigo" | "orange";
  icon: string;
};

export type Recap = {
  id: string;
  shortDay: string;
  date: string;
  score: number;
  status: string;
  sleep: string;
  efficiency: string;
  bedtime: string;
  wakeTime: string;
  timeInBed: string;
  comparison: string;
  insight: string;
  movement: MovementMetric[];
};

export const recaps: Recap[] = [
  {
    id: "recovery",
    shortDay: "Mon",
    date: "Monday, July 13",
    score: 67,
    status: "Take recovery seriously",
    sleep: "5h 54m",
    efficiency: "89%",
    bedtime: "12:46 AM",
    wakeTime: "7:22 AM",
    timeInBed: "6h 38m",
    comparison: "48m below your average",
    insight: "Sleep and movement were both below baseline. An easier day would help you reset.",
    movement: [
      { label: "Steps", value: "6,240", average: "8,590 avg", delta: "2,350 below average", progress: 58, tone: "teal", icon: "↗" },
      { label: "Walking distance", value: "3.1 mi", average: "4.2 mi avg", delta: "1.1 mi below average", progress: 63, tone: "indigo", icon: "⌁" },
      { label: "Active energy", value: "365 kcal", average: "480 kcal avg", delta: "115 kcal below average", progress: 66, tone: "orange", icon: "◒" },
    ],
  },
  {
    id: "balanced",
    shortDay: "Tue",
    date: "Tuesday, July 14",
    score: 86,
    status: "Well recovered",
    sleep: "7h 3m",
    efficiency: "97%",
    bedtime: "11:52 PM",
    wakeTime: "7:10 AM",
    timeInBed: "7h 18m",
    comparison: "21m above your average",
    insight: "Your sleep was more efficient than usual, and you paired it with an above-average movement day.",
    movement: [
      { label: "Steps", value: "9,830", average: "8,590 avg", delta: "1,240 above average", progress: 82, tone: "teal", icon: "↗" },
      { label: "Walking distance", value: "4.6 mi", average: "4.2 mi avg", delta: "0.4 mi above average", progress: 76, tone: "indigo", icon: "⌁" },
      { label: "Active energy", value: "520 kcal", average: "480 kcal avg", delta: "40 kcal above average", progress: 74, tone: "orange", icon: "◒" },
    ],
  },
  {
    id: "active",
    shortDay: "Wed",
    date: "Wednesday, July 15",
    score: 78,
    status: "Solid foundation",
    sleep: "6h 41m",
    efficiency: "94%",
    bedtime: "12:11 AM",
    wakeTime: "7:18 AM",
    timeInBed: "7h 7m",
    comparison: "1m below your average",
    insight: "Movement was the standout today. Your sleep stayed close enough to baseline to support it.",
    movement: [
      { label: "Steps", value: "12,480", average: "8,710 avg", delta: "3,770 above average", progress: 96, tone: "teal", icon: "↗" },
      { label: "Walking distance", value: "6.3 mi", average: "4.3 mi avg", delta: "2.0 mi above average", progress: 94, tone: "indigo", icon: "⌁" },
      { label: "Active energy", value: "690 kcal", average: "490 kcal avg", delta: "200 kcal above average", progress: 92, tone: "orange", icon: "◒" },
    ],
  },
];
