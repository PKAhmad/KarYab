enum DocumentTemplate {
  // German ATS style: blue section header labels, single column, dates
  // left-aligned, no photo.
  atsBlue,
  // Dark navy left sidebar with circular photo; contact/education/skills/
  // languages in the sidebar, experience on the right with timeline dots.
  darkSidebar,
  // Navy header block across the top with photo overlapping, light grey
  // left sidebar, right column with icon section headers + timeline.
  navyHeader,
  // Blue triangle corner top-left, circular photo, name in blue below,
  // left sidebar, right column with icon section headers.
  blueTriangle,
  // "Braun Icon-Set" — light grey/beige left panel, bold brown serif-style
  // name headline, icon-labeled contact block; shares its visual identity
  // with AnschreibenTemplate.braunIconSet and the matching Deckblatt
  // generator (generateDeckblattBraunIconSet), all in cv_pdf_generator.dart.
  braunIconSet,
  // "Weiß Braun Schlicht" — light grey top band with a large bold brown
  // "LEBENSLAUF" headline, single-column body below (icon-prefixed contact
  // lines in Persönliche Daten, brown section headers). Shares its visual
  // identity with AnschreibenTemplate.weissBraunSchlicht and
  // DeckblattTemplate.weissBraunSchlicht, all in cv_pdf_generator.dart.
  weissBraunSchlicht,
}

extension DocumentTemplateInfo on DocumentTemplate {
  String get displayName {
    switch (this) {
      case DocumentTemplate.atsBlue:
        return 'ATS Blue';
      case DocumentTemplate.darkSidebar:
        return 'Dark Sidebar';
      case DocumentTemplate.navyHeader:
        return 'Navy Header';
      case DocumentTemplate.blueTriangle:
        return 'Blue Triangle';
      case DocumentTemplate.braunIconSet:
        return 'Braun Icon-Set';
      case DocumentTemplate.weissBraunSchlicht:
        return 'Weiß Braun Schlicht';
    }
  }

  String get thumbnailAsset {
    switch (this) {
      case DocumentTemplate.atsBlue:
        return 'assets/templates/thumbnails/ats_blue.png';
      case DocumentTemplate.darkSidebar:
        return 'assets/templates/thumbnails/dark_sidebar.png';
      case DocumentTemplate.navyHeader:
        return 'assets/templates/thumbnails/navy_header.png';
      case DocumentTemplate.blueTriangle:
        return 'assets/templates/thumbnails/blue_triangle.png';
      case DocumentTemplate.braunIconSet:
        return 'assets/templates/thumbnails/braun_icon_set.png';
      case DocumentTemplate.weissBraunSchlicht:
        return 'assets/templates/thumbnails/weiss_braun_schlicht.png';
    }
  }

  // Deliberately no shared prefsKey constant here — each independent flow
  // that persists a DocumentTemplate choice (regular CV, and separately
  // Ausbildung) must supply its own distinct SharedPreferences key so their
  // selections never share or clobber each other's state.
  String get storageKey => name;

  static DocumentTemplate fromStorageKey(String? key) {
    return DocumentTemplate.values.firstWhere(
      (t) => t.name == key,
      orElse: () => DocumentTemplate.atsBlue,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Anschreiben (Cover Letter) templates — separate enum from DocumentTemplate
// since generateAnschreiben() takes different data (target position,
// attachments list) than generateCv(), but mirrors the exact same
// displayName/thumbnailAsset/storageKey/fromStorageKey pattern so the
// existing picker UI conventions (document_template_picker.dart) extend to
// it directly.
// ─────────────────────────────────────────────────────────────────────────────

enum AnschreibenTemplate {
  // Sender block top-right in blue bold text, recipient top-left plain
  // black, right-aligned date, bold blue Betreff line.
  blauMinimal,
  // Cream/beige top tint, small grey sender contact top-right, bold black
  // subject line, faint neutral watermark bottom-right corner.
  beigeEleganz,
  // Large bold 2-line sender-name headline (not boxed), "Anlagen:" list at
  // the bottom, dynamically populated from the user's generated documents.
  boldHeadlineGrau,
  // Left third grey/beige panel: bold brown serif name headline + subtitle
  // + icon-labeled contact block; recipient/date/subject/body on the right.
  // Shares its visual identity with DocumentTemplate.braunIconSet and
  // generateDeckblattBraunIconSet.
  braunIconSet,
  // Thin divider bar near the top; sender name/contact in a small bordered
  // box with contact icons; italic right-aligned date.
  grauSchlicht,
  // Grey vertical panel on the right (sender contact + date), large bold
  // brown 2-line "Hallo, ich bin..." headline spanning the full width;
  // recipient/subject/body/closing on the left. Shares its visual identity
  // with DocumentTemplate.weissBraunSchlicht and
  // DeckblattTemplate.weissBraunSchlicht.
  weissBraunSchlicht,
}

extension AnschreibenTemplateInfo on AnschreibenTemplate {
  String get displayName {
    switch (this) {
      case AnschreibenTemplate.blauMinimal:
        return 'Blau Minimal';
      case AnschreibenTemplate.beigeEleganz:
        return 'Beige Eleganz';
      case AnschreibenTemplate.boldHeadlineGrau:
        return 'Bold Headline Grau';
      case AnschreibenTemplate.braunIconSet:
        return 'Braun Icon-Set';
      case AnschreibenTemplate.grauSchlicht:
        return 'Grau Schlicht';
      case AnschreibenTemplate.weissBraunSchlicht:
        return 'Weiß Braun Schlicht';
    }
  }

  String get thumbnailAsset {
    switch (this) {
      case AnschreibenTemplate.blauMinimal:
        return 'assets/templates/thumbnails/anschreiben_blau_minimal.png';
      case AnschreibenTemplate.beigeEleganz:
        return 'assets/templates/thumbnails/anschreiben_beige_eleganz.png';
      case AnschreibenTemplate.boldHeadlineGrau:
        return 'assets/templates/thumbnails/anschreiben_bold_headline_grau.png';
      case AnschreibenTemplate.braunIconSet:
        return 'assets/templates/thumbnails/anschreiben_braun_icon_set.png';
      case AnschreibenTemplate.grauSchlicht:
        return 'assets/templates/thumbnails/anschreiben_grau_schlicht.png';
      case AnschreibenTemplate.weissBraunSchlicht:
        return 'assets/templates/thumbnails/anschreiben_weiss_braun_schlicht.png';
    }
  }

  String get storageKey => name;

  static AnschreibenTemplate fromStorageKey(String? key) {
    return AnschreibenTemplate.values.firstWhere(
      (t) => t.name == key,
      orElse: () => AnschreibenTemplate.blauMinimal,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Deckblatt templates — its own enum, same pattern again. Only introduced
// now that a second real design exists (weissBraunSchlicht) alongside the
// original braunIconSet; before that there was nothing to pick between.
// ─────────────────────────────────────────────────────────────────────────────

enum DeckblattTemplate {
  // Left-third grey/beige panel: name headline + subtitle + icon contact
  // block; "Anlagen:" list on the right. Matches DocumentTemplate.braunIconSet
  // and AnschreibenTemplate.braunIconSet.
  braunIconSet,
  // Left-third grey panel with the name headline + subtitle straddling into
  // the white area; icon contact block and "Anlagen:" list below, in the
  // white area. Matches DocumentTemplate.weissBraunSchlicht and
  // AnschreibenTemplate.weissBraunSchlicht.
  weissBraunSchlicht,
}

extension DeckblattTemplateInfo on DeckblattTemplate {
  String get displayName {
    switch (this) {
      case DeckblattTemplate.braunIconSet:
        return 'Braun Icon-Set';
      case DeckblattTemplate.weissBraunSchlicht:
        return 'Weiß Braun Schlicht';
    }
  }

  String get thumbnailAsset {
    switch (this) {
      case DeckblattTemplate.braunIconSet:
        return 'assets/templates/thumbnails/deckblatt_braun_icon_set.png';
      case DeckblattTemplate.weissBraunSchlicht:
        return 'assets/templates/thumbnails/deckblatt_weiss_braun_schlicht.png';
    }
  }

  String get storageKey => name;

  static DeckblattTemplate fromStorageKey(String? key) {
    return DeckblattTemplate.values.firstWhere(
      (t) => t.name == key,
      orElse: () => DeckblattTemplate.braunIconSet,
    );
  }
}
