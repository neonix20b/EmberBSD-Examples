<?xml version="1.0"?>
<!-- Preserve installed schemas and restore only missing GNOME 40 entries. -->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
  <xsl:param name="legacy"/>
  <xsl:template match="@*|node()">
    <xsl:copy><xsl:apply-templates select="@*|node()"/></xsl:copy>
  </xsl:template>
  <xsl:template match="schemalist">
    <xsl:variable name="current" select="."/>
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
      <xsl:copy-of select="document($legacy)/schemalist/schema[not(@id = $current/schema/@id)]"/>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="schema">
    <xsl:variable name="current" select="."/>
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
      <xsl:copy-of select="document($legacy)/schemalist/schema[@id = $current/@id]/key[not(@name = $current/key/@name)]"/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
