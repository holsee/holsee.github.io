---
title: "ElixirConfEU - Elixir Processes in 3D"
description: "A lightning talk at ElixirConfEU on visualizing Elixir processes in 3D."
tags:
  - elixir
---
<p>I gave a lightning talk at <a href="http://ElixirConf.eu">ElixirConfEU</a> on Visualizing Elixir Processes in 3D.</p>

<p><img class="center" src="/images/exconfeu/elixirconf_lightning_talk.jpg" alt="Giving the lightning talk at ElixirConfEU"></p>

<p>A few nights before travelling to Krakow I had watched a video by <a href="https://github.com/krestenkrab/">Kresten Krab Thorup</a> on his project <a href="https://github.com/krestenkrab/erlubi">Erlubi</a> which transmits basic details of the Erlang VM to a <a href="http://ubietylab.net">Ubigrpah Server</a>.</p>

<p>I started to use this to inspect Erlang projects, and play about with OTP Supervisor trees and how they looked in 3D.</p>

<p>I decided to go about using this from elixir.  It doesn&rsquo;t take much to use from elixir; if you want to visualize your own project simply cherry pick the steps 1, 3, 6 and 7 below.</p>

<p><em>1</em> Download the Ubigraph server from <a href="http://ubietylab.net">ubietylab.net</a>. Unpack it and just run the command line tool <code>bin/ubigraph_server</code>. A black window will appear.</p>

<p><em>2</em> Create a new elixir project <code>mix new lightning_ex</code> and cd into directory.</p>

<p><em>3</em> Add Erlubi as a dependency to the mix.exs file:</p>

<figure class='code'><figcaption><span></span></figcaption><div class="highlight"><table><tr><td class="gutter"><pre class="line-numbers"><span class='line-number'>1</span>
<span class='line-number'>2</span>
<span class='line-number'>3</span>
</pre></td><td class='code'><pre><code class='elixir'><span class='line'><span class="k">defp</span> <span class="n">deps</span> <span class="k">do</span>
</span><span class='line'><span class="k">  </span><span class="p">[{</span><span class="ss">:erlubi</span><span class="p">,</span> <span class="ss">github:</span> <span class="s2">&quot;krestenkrab/erlubi&quot;</span><span class="p">}]</span>
</span><span class='line'><span class="k">end</span>
</span></code></pre></td></tr></table></div></figure>


<p><em>4</em> Add some code to ex_lightning.ex to generate linked and unlinking procs</p>

<figure class='code'><figcaption><span></span></figcaption><div class="highlight"><table><tr><td class="gutter"><pre class="line-numbers"><span class='line-number'>1</span>
<span class='line-number'>2</span>
<span class='line-number'>3</span>
<span class='line-number'>4</span>
<span class='line-number'>5</span>
<span class='line-number'>6</span>
<span class='line-number'>7</span>
<span class='line-number'>8</span>
<span class='line-number'>9</span>
<span class='line-number'>10</span>
<span class='line-number'>11</span>
<span class='line-number'>12</span>
<span class='line-number'>13</span>
<span class='line-number'>14</span>
<span class='line-number'>15</span>
<span class='line-number'>16</span>
<span class='line-number'>17</span>
</pre></td><td class='code'><pre><code class='elixir'><span class='line'><span class="k">defmodule</span> <span class="no">ExLightning</span> <span class="k">do</span>
</span><span class='line'><span class="k">  def</span> <span class="n">start_linked</span><span class="p">(</span><span class="n">n</span><span class="p">)</span> <span class="k">do</span>
</span><span class='line'><span class="k">    </span><span class="n">for</span> <span class="n">_</span> <span class="o">&lt;-</span> <span class="m">1</span><span class="o">..</span><span class="n">n</span> <span class="k">do</span>
</span><span class='line'><span class="k">      </span><span class="no">Task</span><span class="o">.</span><span class="n">start_link</span><span class="p">(</span><span class="k">fn</span> <span class="o">-&gt;</span>
</span><span class='line'>        <span class="ss">:timer</span><span class="o">.</span><span class="n">sleep</span><span class="p">(</span><span class="m">1000</span><span class="p">)</span>
</span><span class='line'>      <span class="k">end</span><span class="p">)</span>
</span><span class='line'>    <span class="k">end</span>
</span><span class='line'>  <span class="k">end</span>
</span><span class='line'>
</span><span class='line'>  <span class="k">def</span> <span class="n">start</span><span class="p">(</span><span class="n">n</span><span class="p">)</span> <span class="k">do</span>
</span><span class='line'><span class="k">    </span><span class="n">for</span> <span class="n">_</span> <span class="o">&lt;-</span> <span class="m">1</span><span class="o">..</span><span class="n">n</span> <span class="k">do</span>
</span><span class='line'><span class="k">      </span><span class="no">Task</span><span class="o">.</span><span class="n">start</span><span class="p">(</span><span class="k">fn</span> <span class="o">-&gt;</span>
</span><span class='line'>        <span class="ss">:timer</span><span class="o">.</span><span class="n">sleep</span><span class="p">(</span><span class="m">1000</span><span class="p">)</span>
</span><span class='line'>      <span class="k">end</span><span class="p">)</span>
</span><span class='line'>    <span class="k">end</span>
</span><span class='line'>  <span class="k">end</span>
</span><span class='line'><span class="k">end</span>
</span></code></pre></td></tr></table></div></figure>


<p><em>5</em> In terminal fetch dependencies and compile with <code>mix do deps.get, compile</code></p>

<p><em>6</em> In terminal start an iex session with mix  <code>iex -S mix</code></p>

<p><em>7</em> In iex session start Erlubi tracer with <code>:erlubi_tracer.run</code>.  If you get an error ensure you started ubigraph_server as described in step 1. At this point you should see the vanilla elixir system visualized in 3D like so:</p>

<ul>
<li>Green Cubes = Erlang Ports</li>
<li>Red Spheres = Erlang Processes</li>
<li>Blue Sphere = Named Erlang Processes</li>
<li>Grey Line   = Process Links</li>
</ul>


<p><img class="center" src="/images/exconfeu/erlubi_vanilla.png" alt="Erlubi 3D visualization: a vanilla process tree"></p>

<p><em>8</em> run <code>ExLightning.start 5000</code> which will create 5000 unlinked processes (unbound red spheres)</p>

<p><img class="center" src="/images/exconfeu/erlubi_unlinked.png" alt="Erlubi 3D visualization: processes without links"></p>

<p><em>9</em> run <code>ExLightning.start_linked 5000</code> which will create 5000 linked processes, which will be linked to the creating process.</p>

<p><img class="center" src="/images/exconfeu/erlubi_linked.png" alt="Erlubi 3D visualization: processes with links shown"></p>

<p>Full source code can be found here: <a href="https://github.com/holsee/lightning_ex">https://github.com/holsee/lightning_ex</a></p>

<p>Have fun :D</p>
</div>


<div class="meta">
	<div class="date">








  


<time datetime="2015-04-28T16:06:04+01:00" pubdate data-updated="true">Apr 28<sup>th</sup>, 2015</time></div>
	

<div class="tags">

	<a class='category' href='/blog/categories/elixir/'>elixir</a>

</div>


	

