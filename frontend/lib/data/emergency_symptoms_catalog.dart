import 'package:flutter/material.dart';

class EmergencySymptom {
  const EmergencySymptom({
    required this.key,
    required this.label,
    required this.icon,
    required this.info,
    this.isNoneOption = false,
  });

  final String key;
  final String label;
  final IconData icon;
  final String info;
  final bool isNoneOption;
}

class EmergencySymptomCategory {
  const EmergencySymptomCategory({
    required this.title,
    required this.symptoms,
  });

  final String title;
  final List<EmergencySymptom> symptoms;
}

/// Catalogue des symptômes d'urgence affichés dans le formulaire patient.
class EmergencySymptomsCatalog {
  EmergencySymptomsCatalog._();

  static const String keyAucun = 'aucun';

  static const EmergencySymptom noneSymptom = EmergencySymptom(
    key: keyAucun,
    label: 'Aucun de ces symptômes',
    icon: Icons.remove_circle_outline_rounded,
    info:
        'Vous ne présentez aucun des symptômes listés et souhaitez continuer vers votre espace patient.',
    isNoneOption: true,
  );

  static const List<EmergencySymptomCategory> categories = [
    EmergencySymptomCategory(
      title: 'Respiratoire',
      symptoms: [
        EmergencySymptom(
          key: 'dyspnee',
          label: 'Dyspnée',
          icon: Icons.air_rounded,
          info: 'Difficulté à respirer ou manque d\'air.',
        ),
        EmergencySymptom(
          key: 'cyanose',
          label: 'Cyanose',
          icon: Icons.water_drop_outlined,
          info: 'Lèvres ou doigts bleus.',
        ),
        EmergencySymptom(
          key: 'toux_severe',
          label: 'Toux sévère',
          icon: Icons.coronavirus_outlined,
          info: 'Toux fréquente et persistante.',
        ),
        EmergencySymptom(
          key: 'respiration_rapide',
          label: 'Respiration rapide',
          icon: Icons.speed_rounded,
          info: 'Respiration accélérée au repos.',
        ),
        EmergencySymptom(
          key: 'detresse_respiratoire',
          label: 'Détresse respiratoire',
          icon: Icons.masks_outlined,
          info: 'Sensation d\'étouffement.',
        ),
      ],
    ),
    EmergencySymptomCategory(
      title: 'Cardiaque',
      symptoms: [
        EmergencySymptom(
          key: 'douleur_thoracique',
          label: 'Douleur thoracique',
          icon: Icons.heart_broken_outlined,
          info: 'Douleur ou pression dans la poitrine.',
        ),
        EmergencySymptom(
          key: 'palpitations',
          label: 'Palpitations',
          icon: Icons.monitor_heart_outlined,
          info: 'Battements du cœur rapides ou irréguliers.',
        ),
        EmergencySymptom(
          key: 'tachycardie',
          label: 'Tachycardie',
          icon: Icons.favorite_outline_rounded,
          info: 'Accélération du rythme cardiaque.',
        ),
        EmergencySymptom(
          key: 'hypotension',
          label: 'Hypotension',
          icon: Icons.arrow_downward_rounded,
          info: 'Baisse de tension avec vertiges ou faiblesse.',
        ),
        EmergencySymptom(
          key: 'oedeme',
          label: 'Œdème',
          icon: Icons.water_outlined,
          info: 'Gonflement des membres ou du visage.',
        ),
      ],
    ),
    EmergencySymptomCategory(
      title: 'Neurologique',
      symptoms: [
        EmergencySymptom(
          key: 'syncope',
          label: 'Syncope',
          icon: Icons.bedtime_outlined,
          info: 'Perte de connaissance temporaire.',
        ),
        EmergencySymptom(
          key: 'convulsions',
          label: 'Convulsions',
          icon: Icons.accessibility_new_rounded,
          info: 'Mouvements involontaires du corps.',
        ),
        EmergencySymptom(
          key: 'hemiplegie',
          label: 'Hémiplégie',
          icon: Icons.accessible_forward_rounded,
          info: 'Paralysie d\'un côté du corps.',
        ),
        EmergencySymptom(
          key: 'trouble_elocution',
          label: 'Trouble de l\'élocution',
          icon: Icons.record_voice_over_outlined,
          info: 'Difficulté à parler correctement.',
        ),
        EmergencySymptom(
          key: 'confusion',
          label: 'Confusion',
          icon: Icons.psychology_alt_outlined,
          info: 'Désorientation ou comportement inhabituel.',
        ),
        EmergencySymptom(
          key: 'cephalee_intense',
          label: 'Céphalée intense',
          icon: Icons.sick_outlined,
          info: 'Mal de tête très fort.',
        ),
      ],
    ),
    EmergencySymptomCategory(
      title: 'Métabolique',
      symptoms: [
        EmergencySymptom(
          key: 'hypoglycemie',
          label: 'Hypoglycémie',
          icon: Icons.bloodtype_outlined,
          info: 'Baisse de sucre provoquant sueurs et tremblements.',
        ),
        EmergencySymptom(
          key: 'hyperglycemie',
          label: 'Hyperglycémie',
          icon: Icons.water_drop_rounded,
          info: 'Excès de sucre avec soif et fatigue.',
        ),
        EmergencySymptom(
          key: 'deshydratation',
          label: 'Déshydratation',
          icon: Icons.local_drink_outlined,
          info: 'Manque d\'eau dans le corps.',
        ),
        EmergencySymptom(
          key: 'asthenie_severe',
          label: 'Asthénie sévère',
          icon: Icons.battery_alert_outlined,
          info: 'Fatigue extrême.',
        ),
      ],
    ),
    EmergencySymptomCategory(
      title: 'Digestif',
      symptoms: [
        EmergencySymptom(
          key: 'douleur_abdominale_aigue',
          label: 'Douleur abdominale aiguë',
          icon: Icons.emergency_outlined,
          info: 'Douleur forte au ventre.',
        ),
        EmergencySymptom(
          key: 'vomissements_incoercibles',
          label: 'Vomissements incoercibles',
          icon: Icons.coronavirus_rounded,
          info: 'Vomissements répétés.',
        ),
        EmergencySymptom(
          key: 'hematemese',
          label: 'Hématémèse',
          icon: Icons.bloodtype_rounded,
          info: 'Vomissement de sang.',
        ),
        EmergencySymptom(
          key: 'diarrhee_severe',
          label: 'Diarrhée sévère',
          icon: Icons.waves_outlined,
          info: 'Diarrhée importante et fréquente.',
        ),
      ],
    ),
    EmergencySymptomCategory(
      title: 'Traumatique',
      symptoms: [
        EmergencySymptom(
          key: 'hemorragie',
          label: 'Hémorragie',
          icon: Icons.bloodtype_outlined,
          info: 'Saignement important.',
        ),
        EmergencySymptom(
          key: 'brulure_grave',
          label: 'Brûlure grave',
          icon: Icons.local_fire_department_outlined,
          info: 'Brûlure profonde ou étendue.',
        ),
        EmergencySymptom(
          key: 'polytraumatisme',
          label: 'Polytraumatisme',
          icon: Icons.personal_injury_outlined,
          info: 'Plusieurs blessures graves.',
        ),
        EmergencySymptom(
          key: 'fracture_suspectee',
          label: 'Fracture suspectée',
          icon: Icons.healing_outlined,
          info: 'Douleur avec impossibilité de bouger.',
        ),
      ],
    ),
    EmergencySymptomCategory(
      title: 'Allergique',
      symptoms: [
        EmergencySymptom(
          key: 'anaphylaxie',
          label: 'Anaphylaxie',
          icon: Icons.warning_amber_rounded,
          info: 'Réaction allergique grave avec gêne respiratoire.',
        ),
        EmergencySymptom(
          key: 'oedeme_du_visage',
          label: 'Œdème du visage',
          icon: Icons.face_outlined,
          info: 'Gonflement rapide du visage ou des lèvres.',
        ),
        EmergencySymptom(
          key: 'urticaire',
          label: 'Urticaire',
          icon: Icons.grain_rounded,
          info: 'Plaques rouges qui grattent.',
        ),
      ],
    ),
    EmergencySymptomCategory(
      title: 'Infectieux',
      symptoms: [
        EmergencySymptom(
          key: 'hyperthermie',
          label: 'Hyperthermie',
          icon: Icons.thermostat_outlined,
          info: 'Fièvre élevée.',
        ),
        EmergencySymptom(
          key: 'frissons',
          label: 'Frissons',
          icon: Icons.ac_unit_rounded,
          info: 'Tremblements liés au froid.',
        ),
        EmergencySymptom(
          key: 'alteration_etat_general',
          label: 'Altération de l\'état général',
          icon: Icons.health_and_safety_outlined,
          info: 'Grande faiblesse ou fatigue intense.',
        ),
      ],
    ),
  ];

  static EmergencySymptom? findByKey(String key) {
    if (key == noneSymptom.key) return noneSymptom;
    for (final category in categories) {
      for (final symptom in category.symptoms) {
        if (symptom.key == key) return symptom;
      }
    }
    return null;
  }

  static String labelForKey(String key) => findByKey(key)?.label ?? key;
}
