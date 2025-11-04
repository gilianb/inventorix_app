enum OrgRole { owner, admin, member, viewer }

class RolePermissions {
  final bool canDeleteLines;
  final bool canEditItems;
  final bool canCreateStock;
  final bool
      canSeeUnitCosts; // unit_cost, unit_fees, shipping/commission/grading_fees
  final bool canSeeFinanceOverview; // widgets KPI/overview (investi/revenus)
  final bool canSeeRevenue; // sale_price / realized_revenue
  final bool canSeeEstimated; // estimated_price

  const RolePermissions({
    required this.canDeleteLines,
    required this.canEditItems,
    required this.canCreateStock,
    required this.canSeeUnitCosts,
    required this.canSeeFinanceOverview,
    required this.canSeeRevenue,
    required this.canSeeEstimated,
  });
}

const Map<OrgRole, RolePermissions> kRoleMatrix = {
  OrgRole.owner: RolePermissions(
    canDeleteLines: true,
    canEditItems: true,
    canCreateStock: true,
    canSeeUnitCosts: true,
    canSeeFinanceOverview: true,
    canSeeRevenue: true,
    canSeeEstimated: true,
  ),
  OrgRole.admin: RolePermissions(
    canDeleteLines: true,
    canEditItems: true,
    canCreateStock: true,
    canSeeUnitCosts: true,
    canSeeFinanceOverview: true,
    canSeeRevenue: true,
    canSeeEstimated: true,
  ),
  OrgRole.member: RolePermissions(
    canDeleteLines: false, // ⬅️ cacher la croix / refuser delete
    canEditItems: true,
    canCreateStock: true,
    canSeeUnitCosts: false, // ⬅️ cacher tous les coûts unitaires & frais
    canSeeFinanceOverview: false, // ⬅️ cacher KPI Investi/Revenue
    canSeeRevenue: true, // à adapter si tu veux aussi cacher les prix de vente
    canSeeEstimated: true, // idem
  ),
  OrgRole.viewer: RolePermissions(
    canDeleteLines: false,
    canEditItems: false,
    canCreateStock: false,
    canSeeUnitCosts: false,
    canSeeFinanceOverview: false,
    canSeeRevenue: false,
    canSeeEstimated: false,
  ),
};
