<?xml version="1.0"?>
<!-- GNOME Shell 40 metadata generated without GLib's GioUnix namespace. -->
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:g="http://www.gtk.org/introspection/core/1.0"
    xmlns:c="http://www.gtk.org/introspection/c/1.0">
  <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
  <xsl:template match="/">
    <xsl:if test="count(g:repository/g:namespace[@name='Shell']/g:class[@name='App']/g:method[@name='get_app_info']) != 1 or count(g:repository/g:namespace[@name='Shell']/g:class[@name='App']/g:property[@name='app-info']) != 1">
      <xsl:message terminate="yes">Unexpected Shell GIR: required App members are absent.</xsl:message>
    </xsl:if>
    <xsl:apply-templates/>
  </xsl:template>
  <xsl:template match="@*|node()">
    <xsl:copy><xsl:apply-templates select="@*|node()"/></xsl:copy>
  </xsl:template>
  <xsl:template match="g:repository">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <xsl:if test="not(g:include[@name='GioUnix'])">
        <include xmlns="http://www.gtk.org/introspection/core/1.0" name="GioUnix" version="2.0"/>
      </xsl:if>
      <xsl:apply-templates select="node()"/>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="g:class[@name='App']/g:method[@name='get_app_info']/@introspectable | g:class[@name='App']/g:property[@name='app-info']/@introspectable"/>
  <xsl:template match="g:class[@name='App']/g:method[@name='get_app_info']/g:return-value/g:type | g:class[@name='App']/g:property[@name='app-info']/g:type">
    <type xmlns="http://www.gtk.org/introspection/core/1.0" name="GioUnix.DesktopAppInfo" c:type="GDesktopAppInfo*"/>
  </xsl:template>
</xsl:stylesheet>
