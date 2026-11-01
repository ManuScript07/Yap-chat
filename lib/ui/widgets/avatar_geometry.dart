/// Matches the 20 / 50 corner proportion of profile and chat controls.
abstract final class AvatarGeometry {
  static const cornerFraction = .4;
  static const profileCornerFraction = .2;

  static double radiusFor(double size) => size * cornerFraction;
  static double profileRadiusFor(double size) => size * profileCornerFraction;
}
